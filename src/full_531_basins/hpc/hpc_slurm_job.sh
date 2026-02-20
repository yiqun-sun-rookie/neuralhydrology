#!/bin/bash
#SBATCH --job-name=neuralhydrology_full_training
#SBATCH --output=logs/neuralhydrology_%j.out
#SBATCH --error=logs/neuralhydrology_%j.err
#SBATCH --time=48:00:00          # 48小时训练时间
#SBATCH --partition=gpu          # GPU分区
#SBATCH --gres=gpu:1             # 申请1个GPU
#SBATCH --mem=32G                # 32GB内存
#SBATCH --cpus-per-task=8        # 8个CPU核心
#SBATCH --nodes=1                # 单节点

# 创建日志目录
mkdir -p logs

# 加载环境
module load python/3.9
module load cuda/11.8

# 激活conda环境
source activate neuralhydrology

# 设置环境变量
export CUDA_VISIBLE_DEVICES=0
export OMP_NUM_THREADS=8

# 进入项目目录
cd /path/to/neuralhydrology

# 运行训练
echo "开始训练: $(date)"
python -m neuralhydrology.nh_run train \
  --config-file src/full_531_basins/configs/camels_us/full_training/full_training_531_temporal_with_static.yml \
  --gpu 0
echo "训练完成: $(date)"

# 可选：发送邮件通知
# mail -s "NeuralHydrology训练完成" your_email@domain.com < logs/neuralhydrology_${SLURM_JOB_ID}.out
