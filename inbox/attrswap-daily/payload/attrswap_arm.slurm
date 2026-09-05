#!/usr/bin/env bash
# One arm of attr_swap_daily_2026_09 on the HPC: train (30 fixed epochs) -> evaluate (test) -> public-422 median.
# Submit as:  sbatch --job-name=<ARM> --export=ALL,ARM=<ARM> job_<ARM>.slurm
# cmd.sh replaces the placeholder line below with "#SBATCH --dependency=afterok:<parity job>" for the 6 arm jobs
# and with an empty line for the parity job. Contract: PREREG_20260901 (laos_forecast/docs/plans).
#SBATCH -p hgpu8
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=8
#SBATCH --gres=gpu:1
#SBATCH --exclude=ngu201
#SBATCH -t 12:00:00
#SBATCH -o /data1/home/sunyiq/attr_swap_daily_2026_09/logs/slurm_%x_%j.out
#SBATCH -e /data1/home/sunyiq/attr_swap_daily_2026_09/logs/slurm_%x_%j.err
__DEPENDENCY_LINE__
set -eo pipefail

ROOT=/data1/home/sunyiq/attr_swap_daily_2026_09
ARM=${ARM:?need ARM via --export=ALL,ARM=...}
PARITY=attrswap_ref27_parity_s900

source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || source $HOME/miniconda3/etc/profile.d/conda.sh
conda activate nh_final || { echo "CONDA_FAILED"; exit 1; }
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
export CUDA_DEVICE_ORDER=PCI_BUS_ID

cd "$ROOT"
export PYTHONPATH="$ROOT/code_1f9804e"

echo "[$(date '+%F %T')] ARM=$ARM JOB=$SLURM_JOB_ID NODE=$(hostname) CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES:-none}"
nvidia-smi --query-gpu=index,name,memory.total,driver_version --format=csv,noheader --id=0 || true
python -u -c "import torch, numpy, pandas, neuralhydrology; print('torch', torch.__version__, 'cuda', torch.cuda.is_available(), 'numpy', numpy.__version__, 'pandas', pandas.__version__, 'nh', neuralhydrology.__file__)"
NHF=$(python -c "import neuralhydrology; print(neuralhydrology.__file__)")
case "$NHF" in "$ROOT/code_1f9804e/"*) echo "neuralhydrology imported from the archived 1f9804e code";; *) echo "WRONG neuralhydrology import path: $NHF -- refusing to train"; exit 4;; esac

if [ "$ARM" != "$PARITY" ]; then
  g="logs/${PARITY}.gate.txt"
  [ -f "$g" ] || { echo "GATE FILE MISSING ($g): parity arm not finished -- refusing to run (resubmit after parity)"; exit 3; }
  grep -qE 'CLEAN|FLAG' "$g" || { echo "GATE HARDFAIL ($(cat "$g")) -- experiment arms must not run"; exit 3; }
  echo "gate: $(cat "$g")"
fi
if [ -f "logs/${ARM}.public_median.txt" ]; then echo "ALREADY DONE: $(cat logs/${ARM}.public_median.txt)"; exit 0; fi

echo "[$(date '+%F %T')] TRAIN $ARM"
python -u -m neuralhydrology.nh_run train --config-file "configs/${ARM}.yml"
rd=$(ls -dt runs/${ARM}_* | sed -n 1p)
[ -n "$rd" ] || { echo "RUN DIR NOT FOUND"; exit 1; }
[ -f "$rd/model_epoch030.pt" ] || { echo "EPOCH-30 WEIGHTS MISSING in $rd"; exit 1; }
echo "[$(date '+%F %T')] EVAL $ARM -> $rd"
python -u -m neuralhydrology.nh_run evaluate --run-dir "$rd" --period test
python -u hpc_gate_median.py "$rd" "$ARM"
echo "[$(date '+%F %T')] DONE $ARM"
