#!/usr/bin/env bash
# Stage-3 P7 (PREREG_20260916 section 8, D18): per-hydrological-year paired differences and baselines computed on the
# HPC from the 26 Stage-2 test_results.p (read-only, 614 MB), writing logs/p7_hydro_year.json (< 100 KB) for retrieval.
# Requests 1 GPU only to run on the chain's partition (pure pandas; <= 20 min; registered outside the V23 ledger).
# No backslash literals anywhere in this file.
#SBATCH -J pswap3_p7
#SBATCH -p __PART__
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=2
#SBATCH --gres=gpu:1
#SBATCH -t 00:20:00
#SBATCH -o /data1/home/sunyiq/precip_swap3_daily_2026_09/logs/slurm_%x_%j.out
#SBATCH -e /data1/home/sunyiq/precip_swap3_daily_2026_09/logs/slurm_%x_%j.err

set -eo pipefail
ROOT=/data1/home/sunyiq/precip_swap3_daily_2026_09
S2=/data1/home/sunyiq/precip_swap2_daily_2026_09
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || source $HOME/miniconda3/etc/profile.d/conda.sh
conda activate nh_final || { echo CONDA_FAILED; exit 1; }
cd "$ROOT"
[ -f "$ROOT/logs/gate_ref.txt" ] || { echo "GATE MARKER MISSING: gate_ref.txt"; exit 3; }
echo "=== P7 on $(hostname) job $SLURM_JOB_ID $(date '+%F %T') ==="
python -u hpc_deploy/p7_hydro_year.py --stage2-runs "$S2/runs" --basins basin_lists/basins_529.txt --holdout basin_lists/holdout_107.txt --streamflow "$ROOT/data_shadow/camels_us/usgs_streamflow" --out logs/p7_hydro_year.json
ls -l logs/p7_hydro_year.json
echo "=== P7 DONE $(date '+%F %T') ==="
