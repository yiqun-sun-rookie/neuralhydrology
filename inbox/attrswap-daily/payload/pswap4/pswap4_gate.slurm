#!/usr/bin/env bash
# GPM-era contract GATE (PREREG_20260927 section 6): build the Daymet-V4 reference + streamflow shadow trees
# (build_shadow4.py), build the six products with the Stage-2 builder (build_precip_swap4.py, dates changed only),
# then run the 7 smoke trainings (5 basins, 1 epoch). Any failure exits non-zero and cancels the array (afterok).
# Writes logs/gate_ok.txt at the end. No backslash literals anywhere in this file.
#SBATCH -J pswap4_gate
#SBATCH -p __PART__
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH -t 03:00:00
#SBATCH -o /data1/home/sunyiq/precip_swap4_gpm_daily_2026_09/logs/slurm_%x_%j.out
#SBATCH -e /data1/home/sunyiq/precip_swap4_gpm_daily_2026_09/logs/slurm_%x_%j.err

set -eo pipefail
ROOT=/data1/home/sunyiq/precip_swap4_gpm_daily_2026_09
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || source $HOME/miniconda3/etc/profile.d/conda.sh
conda activate nh_final || { echo CONDA_FAILED; exit 1; }
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
cd "$ROOT"
export PYTHONPATH="$ROOT/code_1f9804e"
SH="$ROOT/data_shadow/camels_us"
echo "=== gate node $(hostname) job $SLURM_JOB_ID $(date '+%F %T') ==="
nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader --id=0 || true
python -u -c "
import pathlib, torch, neuralhydrology
p = pathlib.Path(neuralhydrology.__file__).as_posix()
assert '/precip_swap4_gpm_daily_2026_09/code_1f9804e/' in p, 'WRONG CODE: ' + p
assert torch.cuda.is_available(), 'NO GPU'
print('archived code OK:', p, 'torch', torch.__version__, torch.cuda.get_device_name(0))
" || exit 4

echo "=== basin lists ==="
[ "$(grep -c . basin_lists/basins_132.txt)" -eq 132 ] || { echo "basins_132 line count FAIL"; exit 1; }
[ "$(grep -c . basin_lists/basins_5.txt)" -eq 5 ] || { echo "basins_5 line count FAIL"; exit 1; }
sha256sum basin_lists/* hpc_deploy/*.gz hpc_deploy/*.json | cut -c1-16,65- | sed 's/^/  /'

echo "=== BUILD reference + streamflow (build_shadow4.py) ==="
python -u hpc_deploy/build_shadow4.py --tables hpc_deploy --dest "$SH" --basins basin_lists/basins_132.txt --report logs/build_shadow4.json

echo "=== BUILD products (build_precip_swap4.py) ==="
for p in gsmap_refday imerg_utc imerg_refday chirps era5l_refday imerg_uncal_refday; do
  extra="--self-aggregated"; [ "$p" = "chirps" ] && extra=""
  tbl="hpc_deploy/${p}_daily_132.csv.gz"
  [ -f "$tbl" ] || { echo "TABLE MISSING: $tbl"; exit 1; }
  echo "--- $p ($extra) table $(sha256sum $tbl | cut -c1-16)"
  python -u hpc_deploy/build_precip_swap4.py "$p" --from-table "$tbl" --ref "$SH/basin_mean_forcing/daymet4" --dest "$SH/basin_mean_forcing" --basins basin_lists/basins_132.txt --report "logs/build_${p}.json" $extra
  hp=$(find "$SH/basin_mean_forcing/$p" -name '*_forcing_leap.txt' | sort | xargs sha256sum | awk '{print $1}' | sha256sum | cut -c1-16)
  echo "  combined hash $p: $hp"
done
hd=$(find "$SH/basin_mean_forcing/daymet4" -name '*_forcing_leap.txt' | sort | xargs sha256sum | awk '{print $1}' | sha256sum | cut -c1-16)
hq=$(find "$SH/usgs_streamflow" -name '*_streamflow_qc.txt' | sort | xargs sha256sum | awk '{print $1}' | sha256sum | cut -c1-16)
echo "  combined hash daymet4: $hd  streamflow: $hq"

echo "=== SMOKE TRAINS (5 basins, 1 epoch) ==="
for f in daymet4 gsmap_refday imerg_utc imerg_refday chirps era5l_refday imerg_uncal_refday; do
  python -u -m neuralhydrology.nh_run train --config-file "configs/pswap4_smoke_${f}.yml" > "logs/smoke_${f}.log" 2>&1 || { echo "SMOKE $f FAILED"; tail -30 "logs/smoke_${f}.log"; exit 1; }
  sd=$(ls -dt runs_smoke/pswap4_smoke_${f}_* 2>/dev/null | head -1) || true
  [ -n "$sd" ] || { echo "SMOKE RUN DIR NOT FOUND $f"; exit 1; }
  python -u -c "
import yaml
c = yaml.safe_load(open('$sd/config.yml'))
assert c['forcings'] == ['$f'], c['forcings']
assert c['dynamic_inputs'][0] == 'prcp(mm/day)', c['dynamic_inputs']
assert str(c['train_start_date'])[:10] in ('2015-10-01', '01/10/2015'), c['train_start_date']
print('smoke $f OK', c['forcings'], c['train_start_date'], c['test_end_date'])
"
  grep -iE "loss|nan" "logs/smoke_${f}.log" | tail -2 | sed 's/^/    /' || true
done
echo "GATE OK $(date '+%F %T') daymet4=$hd streamflow=$hq" > "$ROOT/logs/gate_ok.txt"
echo "=== GATE DONE ==="
