#!/bin/bash
# seq=65 ID35: submit G1 + 7 seeds as 3 packed jobs (smoke 226117 passed).
set -o pipefail
ROOT=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo
cd "$ROOT" || exit 1
echo "=== STAMP ==="; date -Iseconds
INFLIGHT=$(squeue -u "$USER" -h -t RUNNING,CONFIGURING -o "%j" 2>/dev/null | grep -c '^id33_' || true)
echo "id33_in_flight_count=${INFLIGHT}"; [ "${INFLIGHT}" = "0" ] || { echo "REFUSING"; exit 1; }
rm -rf results/35_grace_input_runoff/_smoke/grace_input_runoff_G1_SMOKE_*   # keep smoke.json, drop the run dir
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh; conda activate nh_final
python -m src.transformer_recipe_repair.scripts.audit_configs 2>&1 | tail -1
JOBS=""
submit () {
  local OUT J
  OUT=$(sbatch --export=ALL,ARMS="$1" --job-name="id33_g1_$2" src/transformer_recipe_repair/hpc/submit_packed_arms.slurm 2>&1)
  J=$(echo "$OUT" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+' || true)
  [ -n "$J" ] || { echo "SUBMIT_FAILED $1: $OUT"; return 1; }
  echo "  $2 ($1) -> $J"; JOBS="$JOBS $J"
}
submit "G1 G1_s200 G1_s300" "a" || exit 1
submit "G1_s400 G1_s500 G1_s600" "b" || exit 1
submit "G1_s700 G1_s800" "c" || exit 1
echo "g1_jobs=$JOBS"
sleep 15; squeue -u "$USER" -o "%.10i %.16j %.3t %.8M %.8N %R" 2>&1 | grep -E 'JOBID|id33_g1|knet' || true
