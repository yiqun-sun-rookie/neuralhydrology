#!/usr/bin/env bash
#SBATCH -J v09stateaudit
#SBATCH -p hgpu2p
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH --exclude=ngu002
#SBATCH -t 1-00:00:00
#SBATCH -o /data1/home/sunyiq/v09_strict/logs/state_diagnostics_audit_%j.out
#SBATCH -e /data1/home/sunyiq/v09_strict/logs/state_diagnostics_audit_%j.err

set -eo pipefail
set +u
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
export PATH=/data1/home/sunyiq/v09_strict/gitenv/bin:$PATH
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
export CUBLAS_WORKSPACE_CONFIG=:4096:8

AUDIT_REPO=/data1/home/sunyiq/v09_strict/audit_v09/neuralhydrology
TRAIN_REPO=/data1/home/sunyiq/v09_strict/codetest/neuralhydrology
FORMAL_ROOT=$TRAIN_REPO/results/26_historical_band_experts/formal_v09
INPUT_ROOT=$FORMAL_ROOT/input_attempt_01
RUN_ORDER=$TRAIN_REPO/src/26_historical_band_experts/configs/formal_v09_run_order.json
DIAGNOSTIC_ROOT=$FORMAL_ROOT/state_diagnostics
REPORT=$FORMAL_ROOT/state_diagnostics_external_audit.json
export PYTHONPATH=$AUDIT_REPO:$AUDIT_REPO/src/26_historical_band_experts:${PYTHONPATH:-}

test -f "$DIAGNOSTIC_ROOT/manifest.json"
test ! -e "$REPORT"
test "$(git -C "$AUDIT_REPO" status --porcelain --untracked-files=all)" = ""
echo "audit_commit=$(git -C "$AUDIT_REPO" rev-parse HEAD) node=$(hostname) start=$(date -Iseconds)"
nvidia-smi --query-gpu=index,name,memory.free --format=csv,noheader
python -u "$AUDIT_REPO/src/26_historical_band_experts/audit_state_diagnostics_formal_v09.py" \
  --input-root "$INPUT_ROOT" \
  --formal-root "$FORMAL_ROOT" \
  --run-order "$RUN_ORDER" \
  --diagnostic-root "$DIAGNOSTIC_ROOT" \
  --report "$REPORT" \
  --device cuda:0
echo "end=$(date -Iseconds)"
