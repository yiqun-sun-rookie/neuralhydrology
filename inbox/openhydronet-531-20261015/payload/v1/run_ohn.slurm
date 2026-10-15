#!/usr/bin/env bash
#SBATCH -J ohn_run
#SBATCH -p hgpu8
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH -t 12:00:00
#SBATCH -o /data1/home/sunyiq/openhydronet_531_20261015/logs/%x-%j.out
#SBATCH -e /data1/home/sunyiq/openhydronet_531_20261015/logs/%x-%j.err
# Generic OpenHydroNet runner: train a config, then infer the final epoch on its test period.
# CONFIG (basename without .yml) is passed via --export=ALL,CONFIG=<name>; job name via -J at submit time.
# No --mem (platform rule). No set -u (breaks conda activate).
set -eo pipefail

ROOT=/data1/home/sunyiq/openhydronet_531_20261015
CONFIG="${CONFIG:?CONFIG not set}"
mkdir -p "$ROOT/logs" "$ROOT/runs"

source ~/miniconda3/etc/profile.d/conda.sh
conda activate nh_final || { echo CONDA_FAILED; exit 1; }
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
export PYTHONPATH="$ROOT/pysite:$ROOT/src/flood-forecasting"
cd "$ROOT"

echo "host=$(hostname) start=$(date --iso-8601=seconds) config=$CONFIG job=$SLURM_JOB_ID"
python -u -c "import torch; print('torch', torch.__version__, 'cuda', torch.cuda.is_available(), torch.cuda.get_device_name(0) if torch.cuda.is_available() else '-')"
nvidia-smi --query-gpu=name,memory.used,memory.total --format=csv --id=0 || true

run_cli() {
  python -u -c 'import sys; sys.argv[0] = "run"; from googlehydrology.run import _main; _main()' "$@"
}
run_cli train --config-file "$ROOT/configs/$CONFIG.yml"

RUN_DIR=$(ls -td "$ROOT"/runs/${CONFIG}_* | head -1)
echo "run_dir=$RUN_DIR"
run_cli infer --run-dir "$RUN_DIR"
echo "done=$(date --iso-8601=seconds)"
