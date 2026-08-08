#!/bin/bash
set -o pipefail

echo "=== IDENTITY ==="
date -Is
hostname
printf 'user=%s\n' "$USER"

echo "=== CURRENT JOBS ==="
squeue -u "$USER" -o '%.18i %.12P %.24j %.10T %.12M %.6D %R' 2>&1

echo "=== PARTITIONS ==="
sinfo -h -o '%12P %10a %12l %6D %8t %N' 2>&1 | head -40

echo "=== ISOLATION GUARD ==="
if [ -e "$HOME/camels_g2_design_20260808" ]; then
  echo "ISOLATED_ROOT_EXISTS"
  ls -ld "$HOME/camels_g2_design_20260808"
else
  echo "ISOLATED_ROOT_ABSENT"
fi

echo "=== SHARED INPUTS ==="
for p in \
  "$HOME/neuralhydrology/data/camels_us" \
  "$HOME/neuralhydrology/results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01/summary/hbv_lite_cma_rising_local_full.csv" \
  "$HOME/neuralhydrology/results/23_camels_switch_confirmation/g1_precheck_v01/g1_precheck.csv" \
  "$HOME/neuralhydrology/results/23_camels_switch_confirmation/g1_precheck_v01/g1_precheck.metadata.json"
do
  if [ -e "$p" ]; then
    ls -ld "$p"
    [ -f "$p" ] && sha256sum "$p"
  else
    echo "MISSING $p"
  fi
done

echo "=== BRANCH REACHABILITY ==="
timeout 60 git ls-remote --heads git@github.com:yiqun-sun-rookie/neuralhydrology.git refs/heads/codex/camels-rising-half-recal 2>&1

echo "=== ENVIRONMENT ==="
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || source "$HOME/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final
python - <<'PY'
import sys
import numpy
import pandas
print('python', sys.version.split()[0])
print('numpy', numpy.__version__)
print('pandas', pandas.__version__)
PY

echo "=== STORAGE ==="
df -h /data1 2>&1 | head -5
