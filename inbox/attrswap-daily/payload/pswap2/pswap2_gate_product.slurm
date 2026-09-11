#!/usr/bin/env bash
# Stage-2 PRODUCT gate (PREREG_20260911 section 6, one job per product): build the Daymet-format product from the
# shipped Earth Engine table (or from the Caravan netCDF for era5l_precip2), run V1-V5/V7/V8/V10/V11 (V12 is
# carried as NaN in the table and counted by V4), then a 5-basin 1-epoch smoke train on that product.
# Submitted with PRODUCT, SRC_MODE (table|caravan) and SELFAGG (0|1) exported. Exit non-zero cancels the product's
# three arms (afterok). No backslash literals anywhere in this file.
#SBATCH -J pswap2_gate
#SBATCH -p __PART__
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH -t 03:00:00
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
SH="$ROOT/data_shadow/camels_us/basin_mean_forcing"
[ -n "$PRODUCT" ] || { echo "PRODUCT not set"; exit 2; }
echo "=== product $PRODUCT src=$SRC_MODE selfagg=$SELFAGG node $(hostname) job $SLURM_JOB_ID $(date '+%F %T') ==="

python -u -c "
import pathlib, neuralhydrology
p = pathlib.Path(neuralhydrology.__file__).as_posix()
assert '/precip_swap2_daily_2026_09/code_1f9804e/' in p, 'WRONG CODE: ' + p
print('archived code OK:', p)
" || exit 4

extra=""
[ "$SELFAGG" = "1" ] && extra="--self-aggregated"
echo "=== BUILD $PRODUCT ==="
if [ "$SRC_MODE" = "caravan" ]; then
  python -u hpc_deploy/build_precip_swap2.py "$PRODUCT" --from-caravan /data1/home/sunyiq/neuralhydrology/data/Caravan/timeseries/netcdf/camels --ref "$SH/daymet" --dest "$SH" --basins basin_lists/basins_529.txt --report "logs/build_${PRODUCT}.json" $extra
else
  tbl="hpc_deploy/${PRODUCT}_daily_529.csv.gz"
  [ -f "$tbl" ] || { echo "TABLE MISSING: $tbl"; exit 1; }
  echo "table sha256: $(sha256sum $tbl | cut -c1-16)"
  python -u hpc_deploy/build_precip_swap2.py "$PRODUCT" --from-table "$tbl" --ref "$SH/daymet" --dest "$SH" --basins basin_lists/basins_529.txt --report "logs/build_${PRODUCT}.json" $extra
fi

echo "=== SMOKE TRAIN (5 basins, 1 epoch, $PRODUCT) ==="
python -u -m neuralhydrology.nh_run train --config-file "configs/pswap2_smoke_${PRODUCT}.yml"
sd=$(ls -dt runs_smoke/pswap2_smoke_${PRODUCT}_* 2>/dev/null | head -1) || true
[ -n "$sd" ] || { echo "SMOKE RUN DIR NOT FOUND"; exit 1; }
grep -E "number_of_basins|forcings:" "$sd/output.log" || true
python -u -c "
import yaml
c = yaml.safe_load(open('$sd/config.yml'))
assert c['forcings'] == ['$PRODUCT'], c['forcings']
assert c['dynamic_inputs'][0] == 'prcp(mm/day)', c['dynamic_inputs']
print('smoke config OK:', c['forcings'], c['dynamic_inputs'])
"
echo "GATE $PRODUCT OK $(date '+%F %T')" > "$ROOT/logs/gate_${PRODUCT}.txt"
echo "=== GATE $PRODUCT DONE ==="
