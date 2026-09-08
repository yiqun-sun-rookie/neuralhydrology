#!/usr/bin/env bash
# One forcing-swap arm: train 30 epochs, evaluate the test period, write the public-422 median.
# Submitted with --export=ALL,CFG=<config stem> and --dependency=afterok:<gate job>.
#SBATCH -J fswap_arm
#SBATCH -p hgpu8
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=8
#SBATCH --gres=gpu:1
#SBATCH --exclude=ngu201
#SBATCH -t 08:00:00
#SBATCH -o /data1/home/sunyiq/forcing_swap_daily_2026_09/logs/slurm_%x_%j.out
#SBATCH -e /data1/home/sunyiq/forcing_swap_daily_2026_09/logs/slurm_%x_%j.err

set -eo pipefail
ROOT=/data1/home/sunyiq/forcing_swap_daily_2026_09
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || source $HOME/miniconda3/etc/profile.d/conda.sh
conda activate nh_final || { echo "CONDA_FAILED"; exit 1; }
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
export CUDA_DEVICE_ORDER=PCI_BUS_ID
cd "$ROOT"
export PYTHONPATH="$ROOT/code_1f9804e"

[ -f "$ROOT/logs/gate.txt" ] || { echo "GATE MARKER MISSING -- refusing to run"; exit 3; }
python -u -c "
import neuralhydrology
p = neuralhydrology.__file__.replace('\\\\', '/')
assert '/forcing_swap_daily_2026_09/code_1f9804e/' in p, 'WRONG CODE: ' + p
print('archived code OK:', p)
" || exit 4

echo "=== $CFG on $(hostname) job $SLURM_JOB_ID $(date '+%F %T') ==="
python -u -m neuralhydrology.nh_run train --config-file "configs/${CFG}.yml"
rd=$(ls -dt runs/${CFG}_* 2>/dev/null | head -1) || true
[ -n "$rd" ] || { echo "RUN DIR NOT FOUND for $CFG"; exit 1; }
echo "run dir: $rd"
python -u -m neuralhydrology.nh_run evaluate --run-dir "$rd" --period test
m=$(python -u scripts_public_median.py "$rd")
echo "$m" > "logs/${CFG}.public_median.txt"
echo "RESULT $CFG public_median_n: $m"
echo "=== ARM DONE $(date '+%F %T') ==="
