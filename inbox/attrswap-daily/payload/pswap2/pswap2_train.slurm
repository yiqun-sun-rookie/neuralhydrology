#!/usr/bin/env bash
# One Stage-2 arm: train 30 epochs, evaluate the test period. Submitted with CFG and GATE (marker file name)
# exported and an afterok dependency on the matching gate. WRITE_MEDIAN=1 only for the 8 reference arms
# (stop condition 5: candidate arms do not write public_median.txt). No backslash literals anywhere in this file.
#SBATCH -J pswap2_arm
#SBATCH -p __PART__
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH -t 08:00:00
#SBATCH -o /data1/home/sunyiq/precip_swap2_daily_2026_09/logs/slurm_%x_%j.out
#SBATCH -e /data1/home/sunyiq/precip_swap2_daily_2026_09/logs/slurm_%x_%j.err

set -eo pipefail
ROOT=/data1/home/sunyiq/precip_swap2_daily_2026_09
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || source $HOME/miniconda3/etc/profile.d/conda.sh
conda activate nh_final || { echo CONDA_FAILED; exit 1; }
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
export CUDA_DEVICE_ORDER=PCI_BUS_ID
cd "$ROOT"
export PYTHONPATH="$ROOT/code_1f9804e"
[ -n "$CFG" ] || { echo "CFG not set"; exit 2; }
[ -n "$GATE" ] || { echo "GATE not set"; exit 2; }
[ -f "$ROOT/logs/$GATE" ] || { echo "GATE MARKER MISSING: $GATE"; exit 3; }
python -u -c "
import pathlib, neuralhydrology
p = pathlib.Path(neuralhydrology.__file__).as_posix()
assert '/precip_swap2_daily_2026_09/code_1f9804e/' in p, 'WRONG CODE: ' + p
print('archived code OK:', p)
" || exit 4

echo "=== $CFG on $(hostname) job $SLURM_JOB_ID $(date '+%F %T') ==="
nvidia-smi --query-gpu=name,driver_version --format=csv,noheader --id=0 || true
python -u -m neuralhydrology.nh_run train --config-file "configs/${CFG}.yml"
rd=$(ls -dt runs/${CFG}_* 2>/dev/null | head -1) || true
[ -n "$rd" ] || { echo "RUN DIR NOT FOUND for $CFG"; exit 1; }
echo "run dir: $rd"
python -u -m neuralhydrology.nh_run evaluate --run-dir "$rd" --period test
if [ "$WRITE_MEDIAN" = "1" ]; then
  m=$(python -u hpc_deploy/scripts_public_median.py "$rd")
  echo "$m" > "logs/${CFG}.public_median.txt"
  echo "RESULT $CFG public_median_n: $m"
else
  echo "RESULT $CFG evaluated (candidate arm: median not printed, stop condition 5)"
fi
echo "=== ARM DONE $(date '+%F %T') ==="
