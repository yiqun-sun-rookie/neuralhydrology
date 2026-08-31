#!/bin/bash
# Read-only Python environment and private-wheel-source audit.
set -o pipefail

ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_20260831
CONDA_ROOT=/data1/home/${USER}/miniconda3

echo "=== UNIQUE ROOT RECHECK ==="
if [ -e "$ROOT" ]; then
  echo "ROOT_EXISTS=$ROOT"
else
  echo "ROOT_ABSENT=$ROOT"
fi

echo "=== INSTALLED ENVIRONMENT VERSIONS ==="
for name in knet_clean neuralhydrology nh_clean nh_final; do
  python_path="$CONDA_ROOT/envs/$name/bin/python"
  echo "--- $name ---"
  if [ ! -x "$python_path" ]; then
    echo "MISSING_PYTHON=$python_path"
    continue
  fi
  "$python_path" - <<'PY' 2>&1 || true
import importlib
import json
import platform
import sys

record = {
    "python": platform.python_version(),
    "python_executable": sys.executable,
}
for module_name in ("numpy", "torch", "psutil"):
    try:
        module = importlib.import_module(module_name)
        record[module_name] = str(module.__version__)
    except Exception as error:
        record[module_name] = f"ERROR:{type(error).__name__}:{error}"
print(json.dumps(record, sort_keys=True))
PY
done

echo "=== PRIVATE PYTORCH WHEEL SOURCE ==="
timeout 45 curl -sSIL -m 40 -o /dev/null \
  -w 'torch_2_2_2_cu121_http=%{http_code} bytes=%{size_download} total=%{time_total}\n' \
  'https://download.pytorch.org/whl/cu121/torch-2.2.2%2Bcu121-cp311-cp311-linux_x86_64.whl' || true

echo "=== PYPI WHEEL SOURCES ==="
for url in \
  'https://pypi.org/simple/numpy/' \
  'https://pypi.org/simple/psutil/'
do
  timeout 45 curl -sSIL -m 40 -o /dev/null \
    -w "$url http=%{http_code} total=%{time_total}\n" "$url" || true
done

echo "=== CURRENT GPU PARTITION STATE ==="
sinfo -o '%.10P %.6a %.6D %.6t %.30N' | grep -E 'PARTITION|hgpu2p' || true

echo "=== AUDIT COMPLETE ==="
