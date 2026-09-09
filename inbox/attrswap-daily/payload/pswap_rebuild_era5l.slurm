#!/usr/bin/env bash
# Rebuild era5l_precip with the corrected builder (source PRCP column located by name, plus the V9 ratio band
# and the V6-hard lag floor). Writes a marker only if every check passes; the three arms depend on afterok.
#SBATCH -J pswap_rebuild
#SBATCH -p hgpu4
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH -t 01:00:00
#SBATCH -o /data1/home/sunyiq/precip_swap_daily_2026_09/logs/slurm_pswap_rebuild_%j.out
#SBATCH -e /data1/home/sunyiq/precip_swap_daily_2026_09/logs/slurm_pswap_rebuild_%j.err

set -eo pipefail
ROOT=/data1/home/sunyiq/precip_swap_daily_2026_09
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || source $HOME/miniconda3/etc/profile.d/conda.sh
conda activate nh_final || { echo CONDA_FAILED; exit 1; }
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
cd "$ROOT"
export PYTHONPATH="$ROOT/code_1f9804e"
SH="$ROOT/data_shadow/camels_us/basin_mean_forcing"

echo "=== node $(hostname) job $SLURM_JOB_ID $(date '+%F %T') ==="
echo "--- source product header (PRCP must be located by name, not by position) ---"
sed -n '4p' "$(find -L "$SH/era5l_caravan" -name '01022500_*_forcing_leap.txt' | head -1)"
sed -n '4p' "$(find -L "$SH/maurer" -name '01022500_*_forcing_leap.txt' | head -1)"

echo "=== REBUILD era5l_precip ==="
python -u hpc_deploy/build_precip_swap.py era5l_precip --from-product era5l_caravan \
  --maurer "$SH/maurer" --dest "$SH" --basins basin_lists/basins_529.txt --report logs/build_era5l_precip.json

echo "--- rebuilt product header + first data line (PRCP must now be rain, not radiation) ---"
f=$(find "$SH/era5l_precip" -name '01022500_*_forcing_leap.txt' | head -1)
sed -n '4p' "$f"; sed -n '5p' "$f"

echo "REBUILD OK $(date '+%F %T')" > "$ROOT/logs/rebuild_era5l.txt"
echo "=== REBUILD DONE ==="
