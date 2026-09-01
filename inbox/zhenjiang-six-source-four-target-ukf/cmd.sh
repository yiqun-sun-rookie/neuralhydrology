#!/bin/bash
set -o pipefail

ROOT=/data1/home/sunyiq/zhenjiang_six_source_four_target_differentiable_ukf_20260901_r1
SOURCE=/data1/home/sunyiq/zhenjiang_d32_differentiable_ukf_20260828_r2/inputs/pre2024-v1

printf '=== CANDIDATE_ROOT ===\n'
if [ -e "$ROOT" ] || [ -L "$ROOT" ]; then
  stat -c 'COLLISION|%F|%s|%n' "$ROOT"
else
  echo 'ABSENT_SAFE_TO_CREATE_LATER'
fi
for candidate in "${ROOT}.partial" "${ROOT}.staging"; do
  if [ -e "$candidate" ] || [ -L "$candidate" ]; then
    stat -c 'STAGING_COLLISION|%F|%s|%n' "$candidate"
  else
    printf 'ABSENT|%s\n' "$candidate"
  fi
done

printf '=== IMMUTABLE_SOURCE ===\n'
for relative in \
  dataset_config.json \
  realtime_features/datong_realtime_features.csv \
  realtime_features/nanjing_realtime_features.csv \
  realtime_features/zhenjiang_realtime_features.csv \
  realtime_features/jiangyin_realtime_features.csv \
  realtime_features/xuliujing_realtime_features.csv \
  realtime_features/wusongkou_realtime_features.csv \
  retrospective_targets/nanjing_retrospective_targets.csv \
  retrospective_targets/zhenjiang_retrospective_targets.csv \
  retrospective_targets/jiangyin_retrospective_targets.csv \
  retrospective_targets/xuliujing_retrospective_targets.csv
do
  path="$SOURCE/$relative"
  if [ -f "$path" ] && [ ! -L "$path" ]; then
    sha256sum "$path"
    stat -c 'BYTES|%s|%n' "$path"
  else
    printf 'MISSING_OR_SYMLINK|%s\n' "$path"
  fi
done

printf '=== STORAGE_AND_QUEUE ===\n'
df -h /data1
sinfo -p hgpu2p,hgpu8 -o '%P|%a|%l|%D|%t|%N' || true
squeue -u "$USER" -o '%i|%j|%T|%P|%N|%M|%l|%R' || true

printf '=== ENVIRONMENT ===\n'
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
python - <<'PY'
import sys

import numpy
import pandas
import scipy
import torch

print('python=' + sys.version.split()[0])
print('numpy=' + numpy.__version__)
print('pandas=' + pandas.__version__)
print('scipy=' + scipy.__version__)
print('torch=' + torch.__version__)
print('torch_compiled_cuda=' + str(torch.version.cuda))
PY
exit 0
