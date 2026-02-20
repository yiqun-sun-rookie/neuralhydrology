#!/usr/bin/env python3
"""
HPC优化的NeuralHydrology训练配置
针对SLURM环境优化的参数设置
"""

# =============================================================================
# HPC优化配置 - 针对SLURM环境
# =============================================================================

# 快速设置
QUICK_MODE = "hpc_full"           # HPC全部模式

# 基础训练参数 - HPC优化
EPOCHS = 200                      # HPC可以训练更长时间
BATCH_SIZE = 512                  # HPC GPU可以使用更大批次
LEARNING_RATE = 0.001             # 稳定的学习率

# 模型配置 - HPC优化
HIDDEN_SIZE = 512                 # HPC可以使用更大的模型
OUTPUT_DROPOUT = 0.2              # 适中的dropout
SEQ_LENGTH = 365                  # 标准序列长度

# 设备配置
USE_GPU = True                    # HPC肯定使用GPU
GPU_ID = 0                        # SLURM分配的GPU

# 优化器配置
OPTIMIZER = 'Adam'                # 稳定的优化器
CLIP_GRADIENT_NORM = 1.0          # 梯度裁剪

# 学习率调度 - HPC优化（更长时间训练）
LR_SCHEDULE = {
    0: 0.001,                     # 初始学习率
    50: 0.0008,                   # 50个epoch后
    100: 0.0005,                  # 100个epoch后
    150: 0.0003,                  # 150个epoch后
    180: 0.0001,                  # 180个epoch后
}

# 验证和保存配置 - HPC优化
VALIDATE_EVERY = 10               # 每10个epoch验证
SAVE_WEIGHTS_EVERY = 20           # 每20个epoch保存
LOG_INTERVAL = 10                 # 日志间隔

# 数据配置 - HPC优化
NUM_WORKERS = 16                  # HPC可以使用更多workers
USE_FULL_DATA = True              # 使用全部674个流域

# 评估指标
METRICS = ['NSE', 'KGE', 'Alpha-NSE', 'RMSE', 'MAE']

# 实验名称
EXPERIMENT_NAME = "hpc_full_674_basins_optimized"

# 数据路径（需要根据HPC环境调整）
DATA_DIR = "/path/to/CAMELS_US"
BASIN_FILE = "/path/to/all_basins.txt"

# HPC特定配置
HPC_OPTIMIZATIONS = {
    "use_mixed_precision": True,   # 使用混合精度训练
    "pin_memory": True,           # 固定内存
    "persistent_workers": True,   # 持久化workers
    "prefetch_factor": 4,         # 预取因子
}

print("🚀 HPC优化配置已加载")
print(f"📊 训练参数: {EPOCHS} epochs, batch_size={BATCH_SIZE}, hidden_size={HIDDEN_SIZE}")
print(f"💾 数据: 674个流域, {NUM_WORKERS}个workers")
print(f"🎯 目标: 长时间稳定训练")
