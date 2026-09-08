#!/bin/bash
# seq=32 read-only pre-deploy probe: is anything id33 in flight, is the landing zone intact
set -o pipefail
ROOT=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo

echo "=== STAMP ==="
date -Iseconds
hostname

echo "=== A. ID33 IN FLIGHT (deploy blocker) ==="
INFLIGHT=$(squeue -u "$USER" -h -t RUNNING,CONFIGURING -o "%j" 2>/dev/null | grep -c '^id33_' || true)
echo "id33_in_flight_count=${INFLIGHT}"
if [ "${INFLIGHT}" = "0" ]; then echo "VERDICT: no id33 job in flight; safe to deploy"; else echo "VERDICT: BLOCKED"; fi

echo "=== B. ALL MY JOBS (do not disturb other sessions) ==="
squeue -u "$USER" -o "%.10i %.20j %.3t %.10M %.9N %R" 2>&1 | head -25 || true

echo "=== C. LANDING ZONE INTACT ==="
ls -d "$ROOT" 2>&1
ls -1 "$ROOT/results/33_transformer_recipe_repair/" 2>&1 | head -12
echo "-- arm run dirs --"
for A in T1 T2 T3 T4 T5 L33; do
  n=$(ls -1d "$ROOT/results/33_transformer_recipe_repair/$A"/*/ 2>/dev/null | wc -l)
  echo "  $A run_dirs=$n"
done

echo "=== D. DO THE RAW VALIDATION PREDICTIONS EXIST (for free re-scoring) ==="
find "$ROOT/results/33_transformer_recipe_repair" -maxdepth 4 -name 'validation_results.p' -printf '%s  %p\n' 2>/dev/null | head -8 || echo "  none"

echo "=== E. PARTITION AVAILABILITY ==="
sinfo -o "%.10P %.6a %.6D %.6t %.28N" 2>&1 | head -12 || true

echo "=== F. TORCH VERSION ONLY (no compute) ==="
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null || source $HOME/miniconda3/etc/profile.d/conda.sh
conda activate nh_final && python -c "import torch;print('torch',torch.__version__)" 2>&1 | tail -2 || echo "  conda/torch check failed"
