#!/bin/bash
set -eo pipefail
sequence=1

echo "=== identity ==="
date -Is
hostname
id

echo "=== isolated root must not exist yet ==="
ROOT=/data1/home/sunyiq/regge_record_length_20260929_001
if test -e "$ROOT"; then
  echo "ROOT_EXISTS $ROOT"
  stat -c '%A %U %G %s %y %n' "$ROOT"
else
  echo "ROOT_ABSENT $ROOT"
fi

echo "=== exact candidate source locations ==="
for path in /data1/home/sunyiq/paper-imm-variable-params /data1/home/sunyiq/paper_imm_variable_params "$HOME/paper-imm-variable-params"; do
  if test -e "$path"; then
    stat -c '%A %U %G %s %y %n' "$path"
  else
    echo "ABSENT $path"
  fi
done

echo "=== partitions ==="
sinfo -h -o '%P|%a|%l|%D|%t|%C'
echo "=== selected nodes ==="
sinfo -h -N -p hcpu48,hcpu48y,hgpu2p -o '%P|%N|%t|%c|%m|%G'
echo "=== scheduler reasons ==="
sinfo -R -h || true
echo "=== user jobs ==="
squeue -u sunyiq -o '%.18i %.12P %.36j %.2t %.10M %.10l %.20R'
echo "=== fair share ==="
sshare -U -P || true
echo "=== data1 space ==="
df -h /data1

echo "=== frozen shared environment identity ==="
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || source "$HOME/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final
python - <<'PY'
import json
import os
import platform
import numpy
import torch

print(json.dumps({
    "python": platform.python_version(),
    "numpy": numpy.__version__,
    "torch": torch.__version__,
    "torch_path": torch.__file__,
    "numpy_path": numpy.__file__,
    "conda_prefix": os.environ.get("CONDA_PREFIX"),
}, sort_keys=True))
PY
