#!/bin/bash
# haihe Gangnan B' residual arm (rs). User-authorized 2026-10-21.
# Deploy payload v2 into NEW subfolders of ROOT (tar -k: never overwrite), submit 12-task array on hgpu8
# (same card type as the finished base/bp runs) + aggregate (afterany). Stops before sbatch if anything exists.
set -o pipefail
CH=haihe-gangnan-bprime-20261021
ROOT=/data1/home/sunyiq/haihe_gangnan_bprime
PAY=$HOME/hpc_mailbox/inbox/$CH/payload/gangnan_bprime_rs_payload.tar.gz
EXP_SHA=0e14b1646c36e7148614b832f2dc9d17d4f556f281d3bd84b443f94c4c6bd607
cd "$ROOT" || { echo "NO_ROOT"; exit 1; }
date -Is

echo "=== PRECHECK ==="
echo "v1 done markers: $(find done -maxdepth 1 -name '*.ok' | wc -l)"
for d in configs_rs code_v2 slurm_v2 data/gangnan_inflow_reported_rs; do
    [ -e "$d" ] && { echo "ALREADY_EXISTS $d -- stopping before any sbatch"; exit 1; }
done
[ -f MANIFEST_v2.sha256 ] && { echo "ALREADY_EXISTS MANIFEST_v2.sha256"; exit 1; }
[ -f "$PAY" ] || { echo "PAYLOAD_MISSING $PAY"; exit 1; }
GOT=$(sha256sum "$PAY" | cut -d' ' -f1)
[ "$GOT" = "$EXP_SHA" ] || { echo "PAYLOAD_SHA_MISMATCH got=$GOT"; exit 1; }

echo "=== DEPLOY (tar -k) ==="
tar -xzkf "$PAY" -C "$ROOT" 2>&1 | grep -v 'implausibly old time stamp' || true
sha256sum -c MANIFEST_v2.sha256 > logs/manifest_v2_check.txt 2>&1 || { echo "MANIFEST_V2_FAILED"; grep -v ': OK$' logs/manifest_v2_check.txt; exit 1; }
echo "manifest v2 OK: $(grep -c ': OK$' logs/manifest_v2_check.txt) files"
[ "$(wc -l < configs_rs/tasks.txt)" -eq 12 ] || { echo "TASKS_NOT_12"; exit 1; }
[ "$(grep -c $'\r' configs_rs/tasks.txt)" -eq 0 ] || { echo "CR_IN_TASKS"; exit 1; }
N1=$(head -1 configs_rs/tasks.txt); [ -f "configs_rs/$N1.yml" ] || { echo "FIRST_CONFIG_MISSING $N1"; exit 1; }
grep -n "^data_dir\|dINQ\|clip_targets" "configs_rs/$N1.yml"

echo "=== HGPU8 ==="
sinfo -p hgpu8 -N -h -O nodelist:10,statecompact:10,gres:14,gresused:24 2>&1

echo "=== SUBMIT ARRAY rs ==="
out=$(sbatch slurm_v2/train_eval_rs.slurm 2>&1); echo "$out" | head -5
ARRAY=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+')
[ -n "$ARRAY" ] || { echo "SUBMIT_FAILED array"; exit 1; }
echo "run_train_eval_rs $ARRAY $(date -Is)" >> logs/submissions.txt

echo "=== SUBMIT AGGREGATE rs (afterany $ARRAY) ==="
sed "2i #SBATCH --dependency=afterany:$ARRAY" slurm_v2/aggregate_rs.slurm > slurm_v2/run_aggregate_rs.slurm
out=$(sbatch slurm_v2/run_aggregate_rs.slurm 2>&1); echo "$out" | head -5
AGG=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+')
[ -n "$AGG" ] || { echo "SUBMIT_FAILED aggregate"; exit 1; }
echo "run_aggregate_rs $AGG $(date -Is)" >> logs/submissions.txt

squeue -j $ARRAY,$AGG -h -o '%i %P %T %R' 2>&1 | head -10
echo "RS_SUBMITTED array=$ARRAY aggregate=$AGG"
