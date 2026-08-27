#!/bin/bash
set -eo pipefail

ROOT="/data1/home/sunyiq/zhenjiang_oyv_v1/repo"
INPUT_DIR="${ROOT}/data/processed/water_level_model_input_v7_beijing_realtime_verified"
TIDE_MODEL="${ROOT}/results/modeling/wusongkou_astronomical_tide_v1_validation/tide_model.json"
KALMANNET_ORIGIN="/data1/home/sunyiq/kalmannet_daily_camels_official_core_a35_20260825/source_seq27/third_party/KalmanNet_TSP_828a2cf/KNet/KalmanNet_nn.py"
NEW_ROOT="/data1/home/sunyiq/zhenjiang_latent_da_20260827"

echo "PROBE2_START $(date -Is)"
echo "HOST $(hostname)"
echo "NEW_ROOT_EXISTS=$(test -e "${NEW_ROOT}" && echo true || echo false)"
echo "PATH_CHECKS"
for required in "${ROOT}" "${INPUT_DIR}" "${TIDE_MODEL}" "${KALMANNET_ORIGIN}"
do
  if [ -e "${required}" ]; then
    echo "FOUND ${required}"
  else
    echo "MISSING ${required}"
  fi
done

echo "INPUT_FILES"
find "${INPUT_DIR}" -maxdepth 2 -type f -printf '%P|%s\n' | sort
echo "INPUT_FILE_COUNT=$(find "${INPUT_DIR}" -maxdepth 2 -type f | wc -l)"
echo "INPUT_TOTAL_BYTES=$(find "${INPUT_DIR}" -maxdepth 2 -type f -printf '%s\n' | awk '{s+=$1} END {print s+0}')"
echo "SMALL_FILE_DIGESTS"
sha256sum "${TIDE_MODEL}" "${KALMANNET_ORIGIN}"

echo "NH_FINAL_RUNTIME"
source "/data1/home/${USER}/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final
python - <<'PY'
import importlib.util
import platform
import sys
import numpy
import pandas
import scipy
import torch
print('python=' + sys.version.split()[0])
print('platform=' + platform.platform())
print('numpy=' + numpy.__version__)
print('pandas=' + pandas.__version__)
print('scipy=' + scipy.__version__)
print('torch=' + torch.__version__)
print('pytest_available=' + str(importlib.util.find_spec('pytest') is not None).lower())
PY
echo "PROBE2_END $(date -Is)"
