#!/usr/bin/env bash
#SBATCH -J gpucheck_ngu009
#SBATCH -p hgpu2
#SBATCH --nodelist=ngu009
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=1
#SBATCH --gres=gpu:1
#SBATCH -t 00:05:00
#SBATCH -o /data1/home/sunyiq/hpc_mailbox/outbox/slurm_%j.out
#SBATCH -e /data1/home/sunyiq/hpc_mailbox/outbox/slurm_%j.err
set -eo pipefail
echo "host=$(hostname)"
nvidia-smi --query-gpu=index,name,driver_version,memory.total --format=csv,noheader || echo NVIDIA_SMI_FAILED
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
python -c "import torch;print('torch',torch.__version__,'cuda',torch.cuda.is_available(),'|',torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'NO GPU')"
