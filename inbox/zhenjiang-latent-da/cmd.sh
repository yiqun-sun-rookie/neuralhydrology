#!/usr/bin/env bash
set -o pipefail

REMOTE_ROOT="/data1/home/sunyiq/zhenjiang_pure_gru_20260827"
INPUT_DIR="/data1/home/sunyiq/zhenjiang_oyv_v1/repo/data/processed/water_level_model_input_v7_beijing_realtime_verified"

echo "=== IDENTITY ==="
id -un
hostname
date -Is

echo "=== PATHS ==="
if [ -e "${REMOTE_ROOT}" ] || [ -L "${REMOTE_ROOT}" ]; then
  echo "REMOTE_ROOT_EXISTS"
else
  echo "REMOTE_ROOT_ABSENT"
fi
if [ -d "${INPUT_DIR}" ]; then
  echo "INPUT_DIR_EXISTS"
  find "${INPUT_DIR}" -maxdepth 2 -type f | wc -l
else
  echo "INPUT_DIR_MISSING"
fi

echo "=== RUNTIME ==="
source "/data1/home/${USER}/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final
python - <<'PY'
import numpy
import pandas
import torch
print("python_runtime=passed")
print("numpy=" + numpy.__version__)
print("pandas=" + pandas.__version__)
print("torch=" + torch.__version__)
PY

echo "=== QUEUE ==="
sinfo -p hgpu2p -h -o '%P|%a|%l|%D|%t|%N' | head -20 || true
echo "PROBE_COMPLETED"
