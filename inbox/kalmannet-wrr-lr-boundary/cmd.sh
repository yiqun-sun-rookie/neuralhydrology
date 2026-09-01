#!/bin/bash
set -o pipefail

DATA_ROOT=/data1/home/sunyiq/knet_project/data/processed/high_flow_aug
TRAIN="$DATA_ROOT/train_win800_19990101_01-20070527_03.pt"
VAL="$DATA_ROOT/val_win800_20070527_04-20090314_13.pt"

echo "=== DATA_SHA256 ==="
sha256sum "$TRAIN" "$VAL"

echo "=== KNET_CLEAN_RUNTIME ==="
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null || source "$HOME/miniconda3/etc/profile.d/conda.sh" 2>/dev/null || true
conda activate knet_clean 2>&1 || { echo CONDA_ACTIVATE_FAILED; exit 1; }
python - <<'PY'
import platform
import sys
import numpy
import torch
import yaml
try:
    import optuna
    optuna_version = optuna.__version__
except Exception as exc:
    optuna_version = f"IMPORT_FAILED:{type(exc).__name__}:{exc}"
print("python", sys.version.replace("\n", " "))
print("platform", platform.platform())
print("torch", torch.__version__)
print("cuda_build", torch.version.cuda)
print("cudnn", torch.backends.cudnn.version())
print("numpy", numpy.__version__)
print("pyyaml", yaml.__version__)
print("optuna", optuna_version)
print("cuda_on_login", torch.cuda.is_available())
PY

echo "=== EXACT_DATA_METADATA ==="
stat -c '%n|bytes=%s|mtime=%y' "$TRAIN" "$VAL"
