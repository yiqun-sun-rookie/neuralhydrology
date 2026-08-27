#!/bin/bash
set -eo pipefail

echo "=== HOST AND RUNNER HEALTH ==="
date -Is
hostname
pwd

echo "=== TARGET DIRECTORY ==="
TARGET=/data1/home/sunyiq/id30_modern_transformer_moe_20260827
if [ -e "$TARGET" ]; then
  find "$TARGET" -maxdepth 2 -type f -printf '%p %s\n' | sort | head -40 || true
else
  echo "TARGET_ABSENT"
fi

echo "=== DATA AND ENVIRONMENT ==="
RAW=/data1/home/sunyiq/neuralhydrology/data/camels_us
test -d "$RAW/basin_mean_forcing/maurer" && echo "MAURER_READY" || echo "MAURER_MISSING"
test -d "$RAW/usgs_streamflow" && echo "TRAINING_SOURCE_READY" || echo "TRAINING_SOURCE_MISSING"
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
python - <<'PY'
import importlib.util
import platform

import pandas
import torch

print("python", platform.python_version())
print("pandas", pandas.__version__)
print("torch", torch.__version__)
print("pyarrow", bool(importlib.util.find_spec("pyarrow")))
print("cuda", torch.cuda.is_available())
PY

echo "=== SCHEDULER ==="
sinfo -h -o '%P %a %l %D %t %G' | head -30 || true
squeue -u sunyiq -h -o '%i %P %j %T %M %R' | head -40 || true
