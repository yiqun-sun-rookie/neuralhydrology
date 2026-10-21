#!/bin/bash
# haihe Gangnan B' (reported-only data). User-authorized 2026-10-21.
# Deploy payload to a NEW root, then submit: smoke -> 24-task array (afterok smoke) -> aggregate (afterany array).
# Not idempotent by design: if ROOT already exists we stop before any sbatch (no double submission).
set -o pipefail
CH=haihe-gangnan-bprime-20261021
ROOT=/data1/home/sunyiq/haihe_gangnan_bprime
PAY=$HOME/hpc_mailbox/inbox/$CH/payload/gangnan_bprime_payload.tar.gz
EXP_SHA=7071af107d8da66a0537065a9d59f89af773777396c1378dfee533e379533353

echo "=== HOST ==="
hostname; date -Is

echo "=== NH REPO (read-only) ==="
cd $HOME/neuralhydrology || { echo "NO_NH_REPO"; exit 1; }
git rev-parse HEAD
git rev-parse --abbrev-ref HEAD
grep -n "def custom_normalization" neuralhydrology/utils/config.py || { echo "MISSING custom_normalization"; exit 1; }
grep -n "def clip_targets_to_zero" neuralhydrology/utils/config.py || { echo "MISSING clip_targets_to_zero"; exit 1; }
cd $HOME

echo "=== GPU PARTITIONS ==="
BEST=hgpu2p; BEST_FREE=-1
for P in hgpu2p hgpu2 hgpu4 hgpu8; do
    echo "--- $P"
    sinfo -p $P -N -h -O nodelist:10,statecompact:10,gres:14,gresused:24 2>&1
    FREE=$(sinfo -p $P -N -h -O statecompact:10,gres:14,gresused:24 2>/dev/null | awk '
        $1 ~ /^(idle|mix)$/ { t=$2; u=$3; sub(/^gpu:/,"",t); sub(/\(.*/,"",t); sub(/,.*/,"",t);
                              sub(/^gpu:/,"",u); sub(/\(.*/,"",u); sub(/,.*/,"",u); f+=t-u }
        END { print f+0 }')
    echo "free_gpus=$FREE"
    if [ "$FREE" -gt "$BEST_FREE" ]; then BEST=$P; BEST_FREE=$FREE; fi
done
[ "$BEST_FREE" -gt 0 ] || BEST=hgpu2p
echo "CHOSEN_PARTITION=$BEST (free_gpus=$BEST_FREE)"

echo "=== MY QUEUE BEFORE ==="
echo "n_my_jobs=$(squeue -u $USER -h | wc -l)"

echo "=== DEPLOY ==="
if [ -e "$ROOT" ]; then
    echo "ROOT_EXISTS $ROOT -- stopping before any sbatch"
    ls -la "$ROOT"
    exit 1
fi
[ -f "$PAY" ] || { echo "PAYLOAD_MISSING $PAY"; exit 1; }
GOT=$(sha256sum "$PAY" | cut -d' ' -f1)
[ "$GOT" = "$EXP_SHA" ] || { echo "PAYLOAD_SHA_MISMATCH got=$GOT"; exit 1; }
mkdir -p "$ROOT"/logs "$ROOT"/runs "$ROOT"/collected "$ROOT"/done "$ROOT"/results || exit 1
tar -xzf "$PAY" -C "$ROOT" || { echo "UNTAR_FAILED"; exit 1; }
cd "$ROOT" || exit 1
sha256sum -c MANIFEST.sha256 > logs/manifest_check.txt 2>&1 || { echo "MANIFEST_CHECK_FAILED"; grep -v ': OK$' logs/manifest_check.txt; exit 1; }
echo "manifest OK: $(grep -c ': OK$' logs/manifest_check.txt) files"
[ "$(wc -l < configs/tasks.txt)" -eq 24 ] || { echo "TASKS_NOT_24"; exit 1; }
grep -n "^data_dir\|^run_dir\|^test_end_date" configs/bp_3h_bp_s42.yml

echo "=== PREPARE SLURM COPIES (partition + dependencies) ==="
for F in smoke train_eval aggregate; do
    sed "s/^#SBATCH -p .*/#SBATCH -p $BEST/" slurm/$F.slurm > slurm/run_$F.slurm || exit 1
done
grep -n "^#SBATCH -p" slurm/run_smoke.slurm slurm/run_train_eval.slurm slurm/run_aggregate.slurm

submit() {  # $1 = script; prints job id or exits
    local out jid
    touch "$ROOT/logs/submission_started_$(basename $1 .slurm)"
    out=$(sbatch "$1" 2>&1); echo "$out" | head -5
    jid=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+')
    [ -n "$jid" ] || { echo "SUBMIT_FAILED $1"; exit 1; }
    echo "$(basename $1 .slurm) $jid $(date -Is)" >> "$ROOT/logs/submissions.txt"
    SUBMITTED=$jid
}

echo "=== SUBMIT SMOKE ==="
submit slurm/run_smoke.slurm; SMOKE=$SUBMITTED
echo "smoke_job=$SMOKE"

echo "=== SUBMIT ARRAY (afterok smoke) ==="
sed -i "2i #SBATCH --dependency=afterok:$SMOKE" slurm/run_train_eval.slurm
head -4 slurm/run_train_eval.slurm
submit slurm/run_train_eval.slurm; ARRAY=$SUBMITTED
echo "array_job=$ARRAY"

echo "=== SUBMIT AGGREGATE (afterany array) ==="
sed -i "2i #SBATCH --dependency=afterany:$ARRAY" slurm/run_aggregate.slurm
submit slurm/run_aggregate.slurm; AGG=$SUBMITTED
echo "aggregate_job=$AGG"

echo "=== QUEUE AFTER ==="
squeue -u $USER -h -o '%i %P %T %j %R' 2>&1 | grep -E "gn_b" || echo "NO_GN_JOBS_VISIBLE"
squeue -j $SMOKE -h --start -o '%i %S' 2>&1 || true
cat "$ROOT/logs/submissions.txt"
echo "ALL_SUBMITTED smoke=$SMOKE array=$ARRAY aggregate=$AGG"
