#!/bin/bash
set -eo pipefail

echo "PROBE_START $(date -Is)"
echo "HOST $(hostname)"
echo "USER $(id -un)"
echo "RUNNER_PROCESSES"
ps -ef | grep hpc_runner_active | grep -v grep || true
echo "PARTITIONS"
sinfo -h -o '%P|%a|%l|%D|%G' | grep -E 'hgpu2p|hgpu4|hgpu8' || true
echo "USER_QUEUE"
squeue -u sunyiq -h -o '%i|%j|%T|%P|%M|%R' || true

echo "CANDIDATE_ZHENJIANG_ROOTS"
for candidate in \
  /data1/home/sunyiq/zhenjiang_oyv_v1 \
  /data1/home/sunyiq/zhenjiang_oyv_qual_20260819 \
  /data1/home/sunyiq/zhenjiang_latent_da_20260827
do
  if [ -e "$candidate" ]; then
    echo "FOUND $candidate"
    find "$candidate" -maxdepth 4 -type f \
      \( -name 'datong_realtime_features.csv' \
      -o -name 'wusongkou_retrospective_targets.csv' \
      -o -name 'tide_model.json' \
      -o -name 'KalmanNet_nn.py' \
      -o -name 'zhenjiang_oyv_v1_data.py' \) \
      -print | sort
  else
    echo "MISSING $candidate"
  fi
done

echo "KALMANNET_SOURCE_CANDIDATES"
find /data1/home/sunyiq -maxdepth 7 -type f -name 'KalmanNet_nn.py' -print 2>/dev/null | sort | head -50 || true

echo "NH_FINAL_RUNTIME"
source /data1/home/sunyiq/anaconda3/etc/profile.d/conda.sh
conda activate nh_final
python - <<'PY'
import platform
import sys
import numpy
import pandas
import torch
print('python=' + sys.version.split()[0])
print('platform=' + platform.platform())
print('numpy=' + numpy.__version__)
print('pandas=' + pandas.__version__)
print('torch=' + torch.__version__)
PY
echo "PROBE_END $(date -Is)"
