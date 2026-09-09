#!/usr/bin/env bash
# Gate: build the two precipitation-swap products, verify them, then a 5-basin 1-epoch smoke train.
# Any failure exits non-zero and the six dependent arms are cancelled by afterok.
#SBATCH -J pswap_gate
#SBATCH -p hgpu8
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH -t 03:00:00
#SBATCH -o /data1/home/sunyiq/precip_swap_daily_2026_09/logs/slurm_pswap_gate_%j.out
#SBATCH -e /data1/home/sunyiq/precip_swap_daily_2026_09/logs/slurm_pswap_gate_%j.err

set -eo pipefail
ROOT=/data1/home/sunyiq/precip_swap_daily_2026_09
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || source $HOME/miniconda3/etc/profile.d/conda.sh
conda activate nh_final || { echo CONDA_FAILED; exit 1; }
export MKL_THREADING_LAYER=GNU MKL_SERVICE_FORCE_INTEL=1 CUDA_DEVICE_ORDER=PCI_BUS_ID
cd "$ROOT"
export PYTHONPATH="$ROOT/code_1f9804e"
SH="$ROOT/data_shadow/camels_us/basin_mean_forcing"

echo "=== node $(hostname) job $SLURM_JOB_ID $(date '+%F %T') ==="
python -u -c "
import torch, neuralhydrology
p = neuralhydrology.__file__.replace('\\','/')
assert '/precip_swap_daily_2026_09/code_1f9804e/' in p, 'WRONG CODE: '+p
print('archived code OK:', p); print('torch', torch.__version__, 'cuda', torch.cuda.is_available())
" || exit 4

echo "=== BUILD chirps (from the shipped Earth Engine table) ==="
python -u hpc_deploy/build_precip_swap.py chirps --from-table hpc_deploy/chirps_daily_529.csv.gz \
  --maurer "$SH/maurer" --dest "$SH" --basins basin_lists/basins_529.txt --report logs/build_chirps.json

echo "=== BUILD era5l_precip (precipitation lifted from the verified era5l_caravan product) ==="
python -u hpc_deploy/build_precip_swap.py era5l_precip --from-product era5l_caravan \
  --maurer "$SH/maurer" --dest "$SH" --basins basin_lists/basins_529.txt --report logs/build_era5l_precip.json

echo "=== SMOKE TRAIN (5 basins, 1 epoch, chirps) ==="
python -u -m neuralhydrology.nh_run train --config-file configs/pswap_smoke.yml
sd=$(ls -dt runs_smoke/pswap_smoke_* 2>/dev/null | head -1) || true
[ -n "$sd" ] || { echo "SMOKE RUN DIR NOT FOUND"; exit 1; }
grep -E "number_of_basins|forcings:" "$sd/output.log" || true
python -u -c "
import yaml; c = yaml.safe_load(open('$sd/config.yml'))
assert c['forcings'] == ['chirps'], c['forcings']
print('smoke forcings OK:', c['forcings'], '| dynamic_inputs:', c['dynamic_inputs'])
"
echo "GATE OK $(date '+%F %T')" > "$ROOT/logs/gate.txt"
echo "=== GATE DONE ==="
