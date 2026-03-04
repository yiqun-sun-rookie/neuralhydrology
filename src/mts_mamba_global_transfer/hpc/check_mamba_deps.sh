#!/usr/bin/env bash
# Check HPC dependencies for MTSMamba (Phase 2v2)
set -euo pipefail

CONDA_ENV="${CONDA_ENV:-nh_final}"
WORKDIR="/data1/home/${USER}/neuralhydrology"
OK=true

echo "=== MTSMamba Dependency Check ==="
echo "Conda env: ${CONDA_ENV}"
echo "Work dir:  ${WORKDIR}"
echo ""

# --- Activate conda (same fallback chain as SLURM script) ---
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null || \
source $HOME/miniconda3/etc/profile.d/conda.sh 2>/dev/null || \
source $HOME/anaconda3/etc/profile.d/conda.sh 2>/dev/null || \
{ module load anaconda3 2>/dev/null && eval "$(conda shell.bash hook)"; } || true

if ! conda activate "${CONDA_ENV}" 2>/dev/null; then
  echo "[FAIL] Cannot activate conda env '${CONDA_ENV}'"
  exit 1
fi
echo "[OK] Conda env '${CONDA_ENV}' activated"

# --- Check Python & PyTorch ---
python -c "import torch; print(f'[OK] PyTorch {torch.__version__}, CUDA available: {torch.cuda.is_available()}')" \
  || { echo "[FAIL] PyTorch not installed"; OK=false; }

# --- Check Mamba backend ---
HAS_MAMBA_SSM=false
HAS_TRANSFORMERS=false

python -c "import mamba_ssm; print(f'[OK] mamba_ssm {mamba_ssm.__version__}')" 2>/dev/null \
  && HAS_MAMBA_SSM=true

python -c "from transformers import MambaConfig, MambaModel; print('[OK] transformers Mamba support')" 2>/dev/null \
  && HAS_TRANSFORMERS=true

if $HAS_MAMBA_SSM; then
  echo "[OK] mamba_ssm available (native CUDA kernels)"
elif $HAS_TRANSFORMERS; then
  echo "[OK] transformers Mamba available (pure-PyTorch fallback)"
else
  echo "[FAIL] No Mamba backend found."
  echo "  Fix: pip install transformers  (recommended for HPC)"
  echo "  Or:  pip install mamba-ssm causal-conv1d>=1.1.0  (requires matching CUDA toolkit)"
  OK=false
fi

# --- Check neuralhydrology installation ---
python -c "from neuralhydrology.modelzoo import get_model; print('[OK] neuralhydrology importable')" \
  || { echo "[FAIL] neuralhydrology not importable. Run: pip install -e ."; OK=false; }

# --- Check MTSMamba model file ---
MTSMAMBA_FILE="${WORKDIR}/neuralhydrology/modelzoo/mtsmamba.py"
if [ -f "${MTSMAMBA_FILE}" ]; then
  echo "[OK] mtsmamba.py exists"
else
  echo "[FAIL] ${MTSMAMBA_FILE} not found. Sync from local machine."
  OK=false
fi

# --- Check HourlyCamelsH dataset file ---
HOURLYCAMELSH_FILE="${WORKDIR}/neuralhydrology/datasetzoo/hourlycamelsh.py"
if [ -f "${HOURLYCAMELSH_FILE}" ]; then
  echo "[OK] hourlycamelsh.py exists"
else
  echo "[FAIL] ${HOURLYCAMELSH_FILE} not found. Must sync full neuralhydrology/ package."
  OK=false
fi

# --- Check config and basin file ---
CONFIG="${WORKDIR}/src/mts_mamba_global_transfer/configs/phase2v2_mtsmamba_camelsh_10b.yml"
BASINS="${WORKDIR}/src/mts_mamba_global_transfer/data/phase2_camelsh_10basins.txt"

[ -f "${CONFIG}" ] && echo "[OK] Config file exists" \
  || { echo "[FAIL] Config not found: ${CONFIG}"; OK=false; }
[ -f "${BASINS}" ] && echo "[OK] Basin file exists" \
  || { echo "[FAIL] Basin file not found: ${BASINS}"; OK=false; }

# --- Check CAMELS-H data ---
DATA_DIR="${WORKDIR}/data/camelsh"
if [ -d "${DATA_DIR}" ]; then
  echo "[OK] CAMELS-H data dir exists"
else
  echo "[WARN] ${DATA_DIR} not found. Ensure data_dir in config is correct."
fi

echo ""
if $OK; then
  echo "=== All checks passed. Ready to submit! ==="
else
  echo "=== Some checks FAILED. Fix issues above before submitting. ==="
  exit 1
fi
