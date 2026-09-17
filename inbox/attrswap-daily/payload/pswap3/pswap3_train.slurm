#!/usr/bin/env bash
# One Stage-3 30-epoch arm: train, evaluate the test period at epoch 30. Submitted with CFG and GATE (marker file
# names, colon-separated when more than one, e.g. GATE=guard_T16_PASS.txt:gate_imerg_e18.txt) exported, and an
# afterok dependency on the matching gate / guard jobs. Candidate arms never write public_median.txt (stop
# condition 5). No backslash literals anywhere in this file.
#SBATCH -J pswap3_arm
#SBATCH -p __PART__
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH -t 08:00:00
#SBATCH -o /data1/home/sunyiq/precip_swap3_daily_2026_09/logs/slurm_%x_%j.out
#SBATCH -e /data1/home/sunyiq/precip_swap3_daily_2026_09/logs/slurm_%x_%j.err

set -eo pipefail
ROOT=/data1/home/sunyiq/precip_swap3_daily_2026_09
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || source $HOME/miniconda3/etc/profile.d/conda.sh
conda activate nh_final || { echo CONDA_FAILED; exit 1; }
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
export CUDA_DEVICE_ORDER=PCI_BUS_ID
cd "$ROOT"
export PYTHONPATH="$ROOT/code_1f9804e"
[ -n "$CFG" ] || { echo "CFG not set"; exit 2; }
[ -n "$GATE" ] || { echo "GATE not set"; exit 2; }
IFS=':' read -r -a gates <<< "$GATE"
for g in "${gates[@]}"; do
  [ -f "$ROOT/logs/$g" ] || { echo "GATE MARKER MISSING: $g"; exit 3; }
done
python -u -c "
import pathlib, neuralhydrology
p = pathlib.Path(neuralhydrology.__file__).as_posix()
assert '/precip_swap3_daily_2026_09/code_1f9804e/' in p, 'WRONG CODE: ' + p
print('archived code OK:', p)
" || exit 4

echo "=== $CFG on $(hostname) job $SLURM_JOB_ID $(date '+%F %T') ==="
nvidia-smi --query-gpu=name,driver_version --format=csv,noheader --id=0 || true
python -u -m neuralhydrology.nh_run train --config-file "configs/${CFG}.yml"
rd=$(ls -dt runs/${CFG}_* 2>/dev/null | head -1) || true
[ -n "$rd" ] || { echo "RUN DIR NOT FOUND for $CFG"; exit 1; }
echo "run dir: $rd"
python -u -m neuralhydrology.nh_run evaluate --run-dir "$rd" --period test
[ -f "$rd/test/model_epoch030/test_metrics.csv" ] || { echo "METRICS MISSING"; exit 1; }
echo "RESULT $CFG evaluated at epoch 30 (median not printed, stop condition 5)"
echo "=== ARM DONE $(date '+%F %T') ==="
