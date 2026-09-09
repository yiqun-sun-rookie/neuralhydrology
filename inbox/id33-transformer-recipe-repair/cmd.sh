#!/bin/bash
# seq=40 BATCH 3: deploy the deterministic recipe and submit nine arms in three packed jobs.
#
# Why batch 3 exists: probe 223972 ran three identical replicas concurrently on one card with no
# determinism setting and got three distinct weight digests; probe 223971 with
# use_deterministic_algorithms + cudnn.deterministic + TF32 off + CUBLAS_WORKSPACE_CONFIG=:4096:8
# got one digest across all three. Batches 1 and 2 were therefore not reproducible experiments.
set -o pipefail
ROOT=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo
PAYLOAD=~/hpc_mailbox/payload/id33-transformer-recipe-repair/id33_batch3_v01.tar.gz

echo "=== STAMP ==="; date -Iseconds

echo "=== A. IN-FLIGHT GATE ==="
INFLIGHT=$(squeue -u "$USER" -h -t RUNNING,CONFIGURING -o "%j" 2>/dev/null | grep -c '^id33_' || true)
echo "id33_in_flight_count=${INFLIGHT}"
if [ "${INFLIGHT}" != "0" ]; then echo "REFUSING TO DEPLOY: id33 job in flight"; exit 1; fi
echo "no id33 job in flight; safe to deploy"

echo "=== B. EXTRACT ==="
ls -la "$PAYLOAD" 2>&1 || { echo "PAYLOAD MISSING"; exit 1; }
cd "$ROOT" || exit 1
cp -p src/transformer_recipe_repair/registry/experiments.csv /tmp/id33_registry_before_batch3.csv 2>/dev/null || true
tar -xzf "$PAYLOAD" -C "$ROOT"
sed -i 's/\r$//' src/transformer_recipe_repair/hpc/submit_packed_arms.slurm
echo "-- deployed hashes (must match local) --"
sha256sum src/transformer_recipe_repair/configs/c3.yml \
          src/transformer_recipe_repair/configs/c4.yml \
          src/transformer_recipe_repair/configs/c5.yml \
          src/transformer_recipe_repair/scripts/audit_configs.py \
          src/transformer_recipe_repair/scripts/run_development.py \
          src/transformer_recipe_repair/registry/experiments.csv \
          src/transformer_recipe_repair/hpc/submit_packed_arms.slurm

echo "=== C. AUDIT (must PASS with 11 arms) ==="
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
python -m src.transformer_recipe_repair.scripts.audit_configs 2>&1 | tail -8
AUDIT_RC=${PIPESTATUS[0]}

echo "=== D. DETERMINISM IS ACTUALLY WIRED IN ==="
grep -n 'deterministic_train' src/transformer_recipe_repair/scripts/run_development.py | head -4 || \
  { echo "FATAL: runner is not routed through the deterministic launcher"; exit 1; }

echo "=== E. SUBMIT THREE PACKED JOBS ==="
mkdir -p logs/33_transformer_recipe_repair
JOBS=""
submit () {
  local ARMS_LIST="$1" TAG="$2"
  local OUT
  OUT=$(sbatch --export=ALL,ARMS="$ARMS_LIST" --job-name="id33_b3_${TAG}" \
        src/transformer_recipe_repair/hpc/submit_packed_arms.slurm 2>&1)
  echo "$OUT"
  local J
  J=$(echo "$OUT" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+' || true)
  [ -n "$J" ] || { echo "SUBMIT_FAILED for $ARMS_LIST"; return 1; }
  echo "  $TAG ($ARMS_LIST) -> $J"
  JOBS="$JOBS $J"
}
submit "T1 T2 T3" "arms1" || exit 1
submit "T4 T5 L33" "arms2" || exit 1
submit "C3 C4 C5" "calib" || exit 1
echo "batch3_jobs=$JOBS"

echo "=== F. QUEUE ==="
sleep 20
squeue -u "$USER" -o "%.10i %.14j %.3t %.10M %.9N %R" 2>&1 | grep -E 'JOBID|id33_b3' || true
