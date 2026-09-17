#!/usr/bin/env bash
# One Stage-3 E3 arm: train 60 epochs (contract-external declared control, PREREG_20260916 section 5), then evaluate
# the test period TWICE -- the epoch-30 checkpoint (same-machine cross-time guard T16 and gap30') and the epoch-60
# checkpoint. Submitted with CFG and GATE exported. No backslash literals anywhere in this file.
#SBATCH -J pswap3_ep60
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
import pathlib, neuralhydrology, yaml
p = pathlib.Path(neuralhydrology.__file__).as_posix()
assert '/precip_swap3_daily_2026_09/code_1f9804e/' in p, 'WRONG CODE: ' + p
c = yaml.safe_load(open('configs/${CFG}.yml'))
assert int(c['epochs']) == 60, c['epochs']
assert int(c['save_weights_every']) == 10, c['save_weights_every']
print('archived code OK:', p, 'epochs', c['epochs'])
" || exit 4

echo "=== $CFG (60 epochs) on $(hostname) job $SLURM_JOB_ID $(date '+%F %T') ==="
nvidia-smi --query-gpu=name,driver_version --format=csv,noheader --id=0 || true
python -u -m neuralhydrology.nh_run train --config-file "configs/${CFG}.yml"
rd=$(ls -dt runs/${CFG}_* 2>/dev/null | head -1) || true
[ -n "$rd" ] || { echo "RUN DIR NOT FOUND for $CFG"; exit 1; }
echo "run dir: $rd"
[ -f "$rd/model_epoch030.pt" ] || { echo "model_epoch030.pt MISSING"; exit 1; }
[ -f "$rd/model_epoch060.pt" ] || { echo "model_epoch060.pt MISSING"; exit 1; }
python -u -m neuralhydrology.nh_run evaluate --run-dir "$rd" --period test --epoch 30
python -u -m neuralhydrology.nh_run evaluate --run-dir "$rd" --period test --epoch 60
[ -f "$rd/test/model_epoch030/test_metrics.csv" ] || { echo "EPOCH-30 METRICS MISSING"; exit 1; }
[ -f "$rd/test/model_epoch060/test_metrics.csv" ] || { echo "EPOCH-60 METRICS MISSING"; exit 1; }
sha256sum "$rd/model_epoch030.pt" "$rd/model_epoch060.pt" | sed 's/^/  weights /'
echo "RESULT $CFG evaluated at epochs 30 and 60"
echo "=== EP60 ARM DONE $(date '+%F %T') ==="
