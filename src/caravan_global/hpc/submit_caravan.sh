#!/bin/bash
#SBATCH --job-name=caravan_train
#SBATCH --output=caravan_%j.log
#SBATCH --error=caravan_%j.err
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --time=48:00:00
#SBATCH --partition=gpu
#SBATCH --gres=gpu:1

# 1. 加载环境 (根据你的集群情况修改，例如 module load anaconda3)
# module load miniconda
# source activate neuralhydrology

# 或者如果使用本地 conda 环境
source ~/.bashrc
conda activate neuralhydrology

# 2. 检查 GPU
echo "Running on host: $(hostname)"
nvidia-smi

# 3. 运行训练
# 注意：确保 configs/caravan/caravan_daily_basemodel.yml 中的 data_dir 指向了 HPC 上的正确路径
python -m neuralhydrology.nh_run train --config-file configs/caravan/caravan_daily_basemodel.yml

