#!/bin/bash
# seq=47 SEED REPLICATION stage 1: 20 trainings in 7 packed jobs, one seed triple per job so a
# partially finished stage still yields complete paired-seed rows. Plus the 25-second
# common-window rescore for batch 3 (T4/L33 are scored on 702 days, the rest on 731).
set -o pipefail
ROOT=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo
PAYLOAD=~/hpc_mailbox/payload/id33-transformer-recipe-repair/id33_seeds_v01.tar.gz

echo "=== STAMP ==="; date -Iseconds

echo "=== A. IN-FLIGHT GATE ==="
INFLIGHT=$(squeue -u "$USER" -h -t RUNNING,CONFIGURING -o "%j" 2>/dev/null | grep -c '^id33_' || true)
echo "id33_in_flight_count=${INFLIGHT}"
if [ "${INFLIGHT}" != "0" ]; then echo "REFUSING TO DEPLOY: id33 job in flight"; exit 1; fi
echo "no id33 job in flight; safe to deploy"

echo "=== B. EXTRACT ==="
ls -la "$PAYLOAD" 2>&1 || { echo "PAYLOAD MISSING"; exit 1; }
cd "$ROOT" || exit 1
tar -xzf "$PAYLOAD" -C "$ROOT"
sed -i 's/\r$//' src/transformer_recipe_repair/hpc/submit_packed_arms.slurm
sha256sum src/transformer_recipe_repair/scripts/audit_configs.py \
          src/transformer_recipe_repair/registry/experiments.csv \
          src/transformer_recipe_repair/hpc/submit_packed_arms.slurm
echo "replica configs deployed: $(ls src/transformer_recipe_repair/configs/*_s[0-9]*.yml | wc -l)"

echo "=== C. AUDIT (must PASS with 31 arms) ==="
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
python -m src.transformer_recipe_repair.scripts.audit_configs 2>&1 | tail -6

echo "=== D. GPU AVAILABILITY ==="
sinfo -p hgpu2p,hgpu2 -N -o "%.10N %.8T" 2>&1 | grep -cE 'idle' | xargs -I{} echo "idle gpu nodes: {}"

echo "=== E. SUBMIT: batch-3 common-window rescore (CPU, seconds) ==="
OUT=$(sbatch src/transformer_recipe_repair/hpc/submit_rescore.slurm 2>&1); echo "$OUT"
echo "$OUT" | grep -qE 'Submitted batch job [0-9]+' || echo "  (rescore submit failed; not fatal)"

echo "=== F. SUBMIT: 7 packed seed jobs ==="
JOBS=""
submit () {
  local ARMS_LIST="$1" TAG="$2" OUT J
  OUT=$(sbatch --export=ALL,ARMS="$ARMS_LIST" --job-name="id33_sd_${TAG}" \
        src/transformer_recipe_repair/hpc/submit_packed_arms.slurm 2>&1)
  J=$(echo "$OUT" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+' || true)
  [ -n "$J" ] || { echo "SUBMIT_FAILED for $ARMS_LIST: $OUT"; return 1; }
  echo "  s${TAG} ($ARMS_LIST) -> $J"; JOBS="$JOBS $J"
}
submit "T2_s200 C4_s200"        "200" || exit 1
submit "T2_s300 C3_s300 C4_s300" "300" || exit 1
submit "T2_s400 C3_s400 C4_s400" "400" || exit 1
submit "T2_s500 C3_s500 C4_s500" "500" || exit 1
submit "T2_s600 C3_s600 C4_s600" "600" || exit 1
submit "T2_s700 C3_s700 C4_s700" "700" || exit 1
submit "T2_s800 C3_s800 C4_s800" "800" || exit 1
echo "seed_jobs=$JOBS"

echo "=== G. QUEUE ==="
sleep 15
squeue -u "$USER" -o "%.10i %.14j %.3t %.8M %.8N %R" 2>&1 | grep -E 'JOBID|id33_' || true
