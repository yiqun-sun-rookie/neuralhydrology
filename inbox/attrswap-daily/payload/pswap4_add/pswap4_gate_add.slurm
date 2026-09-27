#!/usr/bin/env bash
# GPM-era contract ADDENDUM GATE (PREREG addendum 2026-09-27): build gsmap_uncal_refday against the existing daymet4
# reference with the Stage-2 builder (--self-aggregated), then one smoke training (5 basins, 1 epoch). Writes
# logs/gate_add_ok.txt. Existing files of the original set are only read. No backslash literals anywhere in this file.
#SBATCH -J pswap4_gate_add
#SBATCH -p hgpu4
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH -t 01:00:00
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

p=gsmap_uncal_refday
[ -f logs/gate_ok.txt ] || { echo "ORIGINAL GATE MARKER MISSING"; exit 1; }
[ -e "$SH/basin_mean_forcing/$p" ] && { echo "REFUSING: $p forcing already exists"; exit 1; }
tbl="hpc_deploy/${p}_daily_132.csv.gz"
[ -f "$tbl" ] || { echo "TABLE MISSING: $tbl"; exit 1; }
echo "--- $p table $(sha256sum $tbl | cut -c1-16)"
python -u hpc_deploy/build_precip_swap4.py "$p" --from-table "$tbl" --ref "$SH/basin_mean_forcing/daymet4" --dest "$SH/basin_mean_forcing" --basins basin_lists/basins_132.txt --report "logs/build_${p}.json" --self-aggregated
hp=$(find "$SH/basin_mean_forcing/$p" -name '*_forcing_leap.txt' | sort | xargs sha256sum | awk '{print $1}' | sha256sum | cut -c1-16)
hd=$(find "$SH/basin_mean_forcing/daymet4" -name '*_forcing_leap.txt' | sort | xargs sha256sum | awk '{print $1}' | sha256sum | cut -c1-16)
echo "  combined hash $p: $hp ; daymet4 unchanged: $hd (expect b498cdc199855a9b)"
[ "$hd" = "b498cdc199855a9b" ] || { echo "DAYMET4 CHANGED"; exit 1; }
python -u -m neuralhydrology.nh_run train --config-file "configs/pswap4_smoke_${p}.yml" > "logs/smoke_${p}.log" 2>&1 || { echo "SMOKE $p FAILED"; tail -30 "logs/smoke_${p}.log"; exit 1; }
sd=$(ls -dt runs_smoke/pswap4_smoke_${p}_* 2>/dev/null | head -1) || true
[ -n "$sd" ] || { echo "SMOKE RUN DIR NOT FOUND"; exit 1; }
python -u -c "
import yaml
c = yaml.safe_load(open('$sd/config.yml'))
assert c['forcings'] == ['$p'], c['forcings']
print('smoke $p OK', c['forcings'], c['train_start_date'], c['test_end_date'])
"
echo "GATE_ADD OK $(date '+%F %T') $p=$hp" > "$ROOT/logs/gate_add_ok.txt"
echo "=== GATE ADD DONE ==="
