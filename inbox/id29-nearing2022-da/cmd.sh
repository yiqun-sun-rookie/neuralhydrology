#!/bin/bash
# ID29 seq=50: read-only artifact-size, storage, queue, and path preflight.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
SIM="$ROOT/results/29_nearing2022_da_ar/nearing2022_simulation_seed0_2026_0808_1535_ep30"
AR="$ROOT/results/29_nearing2022_da_ar/nearing2022_autoregression_lead1_holdout0.0_seed0_2026_0808_1648_ep30"
DA="$ROOT/results/29_nearing2022_da_ar/assimilation_lead_1_holdout_0.0_from_nearing2022_simulation_seed0_2026_0808_1535_ep30"

echo "=== RUNNER ==="
date --iso-8601=seconds
hostname

echo "=== STORAGE ==="
df -h "$ROOT" | tail -2
du -sh "$SIM" "$AR" "$DA"

echo "=== QUEUE ==="
squeue -u "$USER" -o '%.12i %.16j %.10P %.12T %.10M %.10l %R' | head -80
sinfo -o '%12P %10a %10l %8D %12T' | head -30

echo "=== REQUIRED ARTIFACTS ==="
for spec in "SIM:$SIM:test_results.p:test_metrics.csv" "AR:$AR:test_results.p:test_metrics.csv" "DA:$DA:test_results_data_assimilation.p:test_metrics_data_assimilation.csv"; do
  IFS=: read -r label run result_name metric_name <<< "$spec"
  echo "--- $label $run ---"
  for rel in \
    config.yml \
    model_epoch030.pt \
    output.log \
    train_data/train_data_scaler.yml \
    test/model_epoch030/test_results.p \
    test/model_epoch030/test_metrics.csv \
    "test/model_epoch030/$result_name" \
    "test/model_epoch030/$metric_name"; do
    if [ -f "$run/$rel" ]; then
      stat -c '%s bytes  %n' "$run/$rel"
    fi
  done
done

echo "=== SOURCE AND ENVIRONMENT ==="
cd "$ROOT"
git rev-parse HEAD 2>/dev/null || true
git status --short 2>/dev/null | head -80 || true
source ~/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
python - <<'PY'
import platform
import torch
import neuralhydrology
print('python=' + platform.python_version())
print('torch=' + torch.__version__)
print('neuralhydrology=' + getattr(neuralhydrology, '__version__', 'unknown'))
print('cuda=' + str(torch.version.cuda))
PY
