#!/usr/bin/env bash
# Stage-3 PRODUCT gate (PREREG_20260916 section 9, one job per forcing product): build the Daymet-format product from
# the shipped table with build_precip_swap3.py (flags by product kind), V25 combined-hash check where a Stage-2
# product is rebuilt, then a 5-basin 1-epoch smoke train. Submitted with PRODUCT and KIND exported:
#   KIND=window   E1 window arm table (imerg_e18 / imerg_local / gsmap_utc / imerg_tau32): --self-aggregated --window-arm
#   KIND=noise    E2 synthetic table (syn_ln*): --synthetic noise
#   KIND=shift1   daymet_shift1: --synthetic shift1
#   KIND=rebuild  Stage-2 product rebuilt for E3 (era5l_refday): --self-aggregated, then V25 combined hash must equal
#                 the registered Stage-2 landing-dir value (V25_HASH exported)
#   KIND=r2       R2 reserve (V14 failed): a Stage-2 window product re-extracted and retrained here; full Stage-2 V11
#                 (NOT rule (f)), --self-aggregated; no V25 comparison (it failed by definition)
# Exit non-zero cancels the product's arms (afterok). No backslash literals anywhere in this file.
#SBATCH -J pswap3_gate
#SBATCH -p __PART__
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH -t 03:00:00
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
SH="$ROOT/data_shadow/camels_us/basin_mean_forcing"
[ -n "$PRODUCT" ] || { echo "PRODUCT not set"; exit 2; }
[ -n "$KIND" ] || { echo "KIND not set"; exit 2; }
echo "=== product $PRODUCT kind=$KIND node $(hostname) job $SLURM_JOB_ID $(date '+%F %T') ==="

python -u -c "
import pathlib, neuralhydrology
p = pathlib.Path(neuralhydrology.__file__).as_posix()
assert '/precip_swap3_daily_2026_09/code_1f9804e/' in p, 'WRONG CODE: ' + p
print('archived code OK:', p)
" || exit 4

case "$KIND" in
  window)  extra="--self-aggregated --window-arm" ;;
  noise)   extra="--synthetic noise" ;;
  shift1)  extra="--synthetic shift1" ;;
  rebuild) extra="--self-aggregated" ;;
  r2)      extra="--self-aggregated" ;;
  *) echo "unknown KIND $KIND"; exit 2 ;;
esac
tbl="hpc_deploy/${PRODUCT}_daily_529.csv.gz"
[ -f "$tbl" ] || { echo "TABLE MISSING: $tbl"; exit 1; }
echo "table sha256: $(sha256sum $tbl | cut -c1-16)"
echo "=== BUILD $PRODUCT ($extra) ==="
python -u hpc_deploy/build_precip_swap3.py "$PRODUCT" --from-table "$tbl" --ref "$SH/daymet" --dest "$SH" --basins basin_lists/basins_529.txt --report "logs/build_${PRODUCT}.json" $extra

hp=$(find "$SH/$PRODUCT" -name '*_forcing_leap.txt' | sort | xargs sha256sum | awk '{print $1}' | sha256sum | cut -c1-16)
echo "combined hash of $PRODUCT forcing files: $hp"
if [ "$KIND" = "rebuild" ]; then
  [ -n "$V25_HASH" ] || { echo "V25_HASH not set for a rebuild"; exit 2; }
  [ "$hp" = "$V25_HASH" ] || { echo "V25 FAIL: rebuilt $PRODUCT combined hash $hp != registered $V25_HASH"; exit 1; }
  echo "V25 OK: rebuilt $PRODUCT byte-identical to the Stage-2 landing dir"
fi

echo "=== SMOKE TRAIN (5 basins, 1 epoch, $PRODUCT) ==="
python -u -m neuralhydrology.nh_run train --config-file "configs/pswap3_smoke_${PRODUCT}.yml"
sd=$(ls -dt runs_smoke/pswap3_smoke_${PRODUCT}_* 2>/dev/null | head -1) || true
[ -n "$sd" ] || { echo "SMOKE RUN DIR NOT FOUND"; exit 1; }
grep -E "number_of_basins|forcings:" "$sd/output.log" || true
python -u -c "
import yaml
c = yaml.safe_load(open('$sd/config.yml'))
assert c['forcings'] == ['$PRODUCT'], c['forcings']
assert c['dynamic_inputs'][0] == 'prcp(mm/day)', c['dynamic_inputs']
print('smoke config OK:', c['forcings'], c['dynamic_inputs'])
"
echo "GATE $PRODUCT OK kind=$KIND hash=$hp $(date '+%F %T')" > "$ROOT/logs/gate_${PRODUCT}.txt"
echo "=== GATE $PRODUCT DONE ==="
