#!/usr/bin/env bash
#SBATCH -J id23accept
#SBATCH -p hcpu48y
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=8
#SBATCH -t 02:00:00
#SBATCH -o /data1/home/sunyiq/hpc_mailbox/outbox/slurm_%j.out
#SBATCH -e /data1/home/sunyiq/hpc_mailbox/outbox/slurm_%j.err
set -eo pipefail

source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null || \
  source $HOME/miniconda3/etc/profile.d/conda.sh
conda activate nh_final

export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
export OMP_NUM_THREADS=8

cd /data1/home/sunyiq/id23_dlimm
export PYTHONPATH=$(pwd)/src:$PYTHONPATH

echo "host=$(hostname) torch=$(python -c 'import torch;print(torch.__version__)')"

echo "--- operator audit (P = I bit identity) ---"
python -u -m hbv_history_conditioned_imm.scripts.audit_h19_forecast_operator \
  --blocks 6 --assimilation-days 60 --origins 12 2>&1 | tail -4

echo "--- stage zero ceiling probe, 200 blocks (migration acceptance) ---"
python -u -m hbv_history_conditioned_imm.scripts.pilot_h19_forecast_window_ceiling \
  --blocks 200 --assimilation-days 300 --bootstrap-draws 20000 2>&1 | grep -E "^  (frozen|evolving)|elapsed" || true
