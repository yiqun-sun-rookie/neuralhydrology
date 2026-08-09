#!/bin/bash
set -eo pipefail

echo "=== RUNNER AND TIME ==="
date
hostname
pgrep -af "hpc_runner_active" || true

echo "=== CURRENT USER JOBS ==="
squeue -u "$USER" -o "%.18i %.24j %.10P %.8T %.10M %.20R" 2>&1 | head -80

echo "=== HGPU2P AVAILABILITY ==="
sinfo -p hgpu2p -N -o "%12N %12P %10T %5c %10G %30E" 2>&1 | head -30

echo "=== ISOLATED TARGET ==="
TARGET=/data1/home/sunyiq/kalmannet_tukf06_20260809
if [ -e "$TARGET" ]; then
  echo "TARGET_EXISTS"
  ls -lad "$TARGET"
else
  echo "TARGET_AVAILABLE=$TARGET"
fi

echo "=== REQUIRED DATA AND PRIOR ==="
for path in \
  /data1/home/sunyiq/neuralhydrology/data/camels_us \
  /data1/home/sunyiq/neuralhydrology/results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01_BEST/summary/hbv_lite_cma_local_full.csv \
  /data1/home/sunyiq/neuralhydrology/src/xaj_global_pilot/configs/conceptual_benchmark_camels_us_531_repro.txt; do
  if [ -e "$path" ]; then
    echo "FOUND $path"
  else
    echo "MISSING $path"
  fi
done

echo "=== ENVIRONMENT ==="
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || source "$HOME/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final
export PYTHONPATH=/data1/home/sunyiq/neuralhydrology/src:${PYTHONPATH:-}
python - <<'PY'
import importlib
import platform
import torch
print("python", platform.python_version())
print("torch", torch.__version__)
print("login_cuda_available", torch.cuda.is_available())
for name in ("numpy", "pandas", "scipy", "hydroagent.data_loading"):
    try:
        module = importlib.import_module(name)
        print("IMPORT_OK", name, getattr(module, "__version__", "no_version"))
    except Exception as exc:
        print("IMPORT_FAIL", name, type(exc).__name__, str(exc)[:200])
PY

echo "=== STORAGE ==="
df -h /data1 2>&1 | head -5
