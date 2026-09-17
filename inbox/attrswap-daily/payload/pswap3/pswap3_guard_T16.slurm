#!/usr/bin/env bash
# Stage-3 same-machine cross-time guard T16 (PREREG_20260916 section 5.3): for each of the 6 E3 arms, the epoch-30
# per-basin NSE is paired with the Stage-2 run of the SAME seed and the public-422 median difference is read.
#   6/6 |d| < 0.006346                 -> CLEAN  (marker logs/guard_T16_PASS.txt, status CLEAN)
#   exactly 1/6 in [0.006346, 0.03)    -> FLAG   (marker written, status FLAG; cross-batch head-to-heads degraded)
#   >= 2/6 in [0.006346, 0.03) or any >= 0.03 -> STOP (no marker, exit 1 -> dependent E1/E2 arms never start)
# Runs after the 6 ep60 arms (afterok). Reads the Stage-2 landing dir read-only. Requests 1 GPU for <= 20 min so that
# it can run on the same partition as the chain (registered outside the V23 ledger, PREREG 18.1). No backslash literals here.
#SBATCH -J pswap3_guard_T16
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
echo "=== guard T16 on $(hostname) job $SLURM_JOB_ID $(date '+%F %T') ==="
# a non-zero exit of the guard script ends this job non-zero (set -e), so the afterok dependents never start (STOP tier)
python -u hpc_deploy/guard_T16.py --stage3-runs runs --stage2-runs "$S2/runs" --holdout basin_lists/holdout_107.txt --basins basin_lists/basins_529.txt --out logs/guard_T16.json --marker logs/guard_T16_PASS.txt
echo "guard finished $(date '+%F %T')"
