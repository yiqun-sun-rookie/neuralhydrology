#!/usr/bin/env bash
# Stage-3 REFERENCE gate (PREREG_20260916 section 9): daymet link chain, V0 basin-list hashes (incl. the fixed
# standard-time grouping table), V9 streamflow registration, then a 5-basin 1-epoch smoke train on daymet.
# Exit non-zero cancels every dependent job (afterok). No backslash literals anywhere in this file.
#SBATCH -J pswap3_gate_ref
#SBATCH -p __PART__
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH -t 02:00:00
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
SH="$ROOT/data_shadow/camels_us"

echo "=== node $(hostname) job $SLURM_JOB_ID $(date '+%F %T') ==="
cat /etc/redhat-release 2>/dev/null || true
nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader --id=0 || true

python -u -c "
import pathlib, torch, neuralhydrology
p = pathlib.Path(neuralhydrology.__file__).as_posix()
assert '/precip_swap3_daily_2026_09/code_1f9804e/' in p, 'WRONG CODE: ' + p
print('archived code OK:', p)
print('torch', torch.__version__, 'cuda', torch.cuda.is_available(), torch.cuda.get_device_name(0))
" || exit 4

echo "=== V0 basin list hashes ==="
h1=$(sha256sum basin_lists/basins_529.txt | cut -c1-16); h2=$(sha256sum basin_lists/holdout_107.txt | cut -c1-16)
h3=$(sha256sum basin_lists/fixed_std_offset_529.csv | cut -c1-16)
echo "basins_529 $h1  holdout_107 $h2  fixed_std_offset_529 $h3"
[ "$h1" = "98018c03b0295a56" ] || { echo "V0 FAIL basins_529"; exit 1; }
[ "$h2" = "44a99ee0a8b42309" ] || [ "$h2" = "305211b0fd256769" ] || { echo "V0 FAIL holdout_107"; exit 1; }
# fixed_std_offset_529.csv is written with LF locally (40ed13356a8a54c5); a CRLF-converted copy is not accepted
[ "$h3" = "40ed13356a8a54c5" ] || { echo "V0 FAIL fixed_std_offset_529"; exit 1; }
[ "$(grep -c . basin_lists/holdout_107.txt)" -eq 107 ] || { echo "V0 FAIL holdout_107 line count"; exit 1; }
[ "$(grep -c . basin_lists/basins_529.txt)" -eq 529 ] || { echo "V0 FAIL basins_529 line count"; exit 1; }

echo "=== daymet link chain ==="
ls -l "$SH" "$SH/basin_mean_forcing" | sed 's/^/  /'
dang=$(find -L "$SH" -type l 2>/dev/null | head -5)
[ -z "$dang" ] || { echo "DANGLING: $dang"; exit 1; }
nd=$(find -L "$SH/basin_mean_forcing/daymet" -name '*_forcing_leap.txt' | wc -l)
echo "daymet files through the link: $nd"
[ "$nd" -eq 677 ] || { echo "DAYMET COUNT FAIL"; exit 1; }
hd=$(find -L "$SH/basin_mean_forcing/daymet" -name '*_forcing_leap.txt' | sort | xargs sha256sum | awk '{print $1}' | sha256sum | cut -c1-16)
echo "daymet combined hash: $hd (Stage-2 landing dir registered 986de3a2387f2798)"
[ "$hd" = "986de3a2387f2798" ] || { echo "V25 FAIL daymet combined hash"; exit 1; }
ns=$(find -L "$SH/usgs_streamflow" -name '*_streamflow_qc.txt' | wc -l)
echo "streamflow files through the chain: $ns"
[ "$ns" -ge 529 ] || { echo "STREAMFLOW COUNT FAIL"; exit 1; }

echo "=== V9 streamflow valid-day registration ==="
python -u hpc_deploy/v9_streamflow.py "$SH/usgs_streamflow" basin_lists/basins_529.txt logs/v9_streamflow.json

echo "=== SMOKE TRAIN (5 basins, 1 epoch, daymet) ==="
python -u -m neuralhydrology.nh_run train --config-file configs/pswap3_smoke_daymet.yml
sd=$(ls -dt runs_smoke/pswap3_smoke_daymet_* 2>/dev/null | head -1) || true
[ -n "$sd" ] || { echo "SMOKE RUN DIR NOT FOUND"; exit 1; }
grep -E "number_of_basins|forcings:" "$sd/output.log" || true
grep -c "case-insensitive" "$sd/output.log" && { echo "LOWERCASE MAPPING FALLBACK WAS USED -- FAIL"; exit 1; } || echo "no case-insensitive fallback: OK"
python -u -c "
import yaml, glob
c = yaml.safe_load(open('$sd/config.yml'))
assert c['forcings'] == ['daymet'], c['forcings']
assert c['dynamic_inputs'][0] == 'prcp(mm/day)', c['dynamic_inputs']
assert str(c['train_start_date'])[:10] in ('2004-10-01', '01/10/2004'), c['train_start_date']
assert int(c['save_weights_every']) == 10, c['save_weights_every']
sf = glob.glob('$sd/train_data/train_data_scaler.*')
assert sf, 'scaler file missing'
print('smoke config OK:', c['forcings'], c['dynamic_inputs'], c['train_start_date'], c['test_end_date'])
"
echo "GATE_REF OK $(date '+%F %T')" > "$ROOT/logs/gate_ref.txt"
echo "=== GATE REF DONE ==="
