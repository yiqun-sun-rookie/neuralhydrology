#!/usr/bin/env bash
# GPM-era contract arm (array task): line SLURM_ARRAY_TASK_ID+1 of configs/arms.txt -> train 30 epochs, evaluate the
# test period at epoch 30. Submitted as --array=0-25%4 with afterok on the gate job; also checks logs/gate_ok.txt.
# Median NSE is never printed. No backslash literals anywhere in this file.
#SBATCH -J pswap4_arm
#SBATCH -p __PART__
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH -t 04:00:00
#SBATCH -o /data1/home/sunyiq/precip_swap4_gpm_daily_2026_09/logs/slurm_%x_%A_%a.out
#SBATCH -e /data1/home/sunyiq/precip_swap4_gpm_daily_2026_09/logs/slurm_%x_%A_%a.err

set -eo pipefail
ROOT=/data1/home/sunyiq/precip_swap4_gpm_daily_2026_09
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || source $HOME/miniconda3/etc/profile.d/conda.sh
conda activate nh_final || { echo CONDA_FAILED; exit 1; }
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
cd "$ROOT"
export PYTHONPATH="$ROOT/code_1f9804e"
[ -f logs/gate_ok.txt ] || { echo "GATE MARKER MISSING"; exit 3; }
[ -n "$SLURM_ARRAY_TASK_ID" ] || { echo "not an array task"; exit 2; }
CFG=$(sed -n "$((SLURM_ARRAY_TASK_ID + 1))p" configs/arms.txt)
[ -n "$CFG" ] || { echo "no config for task $SLURM_ARRAY_TASK_ID"; exit 2; }
[ -f "configs/${CFG}.yml" ] || { echo "config file missing: $CFG"; exit 2; }
echo "=== task $SLURM_ARRAY_TASK_ID cfg $CFG node $(hostname) job $SLURM_JOB_ID $(date '+%F %T') ==="
python -u -c "
import pathlib, torch, neuralhydrology
p = pathlib.Path(neuralhydrology.__file__).as_posix()
assert '/precip_swap4_gpm_daily_2026_09/code_1f9804e/' in p, 'WRONG CODE: ' + p
assert torch.cuda.is_available(), 'NO GPU'
print('archived code OK', torch.cuda.get_device_name(0))
" || exit 4
python -u -m neuralhydrology.nh_run train --config-file "configs/${CFG}.yml"
rd=$(ls -dt runs/${CFG}_* 2>/dev/null | head -1) || true
[ -n "$rd" ] || { echo "RUN DIR NOT FOUND for $CFG"; exit 1; }
echo "run dir: $rd"
python -u -m neuralhydrology.nh_run evaluate --run-dir "$rd" --period test
[ -f "$rd/test/model_epoch030/test_metrics.csv" ] || { echo "METRICS MISSING"; exit 1; }
echo "RESULT $CFG evaluated at epoch 30 rows $(wc -l < $rd/test/model_epoch030/test_metrics.csv)"
echo "=== ARM DONE $(date '+%F %T') ==="
