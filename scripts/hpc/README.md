# HPC 相关文件

## 📁 目录结构

```
scripts/
└── hpc/
    ├── hpc_optimized_config.py    # HPC优化配置
    ├── hpc_slurm_job.sh          # SLURM作业脚本
    └── README.md                 # 本说明文件
```

## 🖥️ 文件说明

### hpc_optimized_config.py
HPC环境下的优化配置脚本，包含：
- 多GPU训练配置
- 分布式训练设置
- 内存优化参数
- 批处理大小调整

### hpc_slurm_job.sh
SLURM作业调度系统的作业脚本，包含：
- 资源申请配置
- 环境设置
- 训练任务提交
- 日志管理

## 🚀 使用方法

### HPC环境配置
```bash
# 检查HPC环境
python scripts/hpc/hpc_optimized_config.py --check

# 生成优化配置
python scripts/hpc/hpc_optimized_config.py --generate-config
```

### SLURM作业提交
```bash
# 提交训练作业
sbatch scripts/hpc/hpc_slurm_job.sh

# 查看作业状态
squeue -u $USER

# 取消作业
scancel <job_id>
```

## ⚙️ 配置说明

### 资源申请
```bash
#SBATCH --nodes=1              # 节点数
#SBATCH --ntasks-per-node=1    # 每节点任务数
#SBATCH --cpus-per-task=8      # CPU核心数
#SBATCH --mem=32G              # 内存大小
#SBATCH --gres=gpu:1           # GPU数量
#SBATCH --time=24:00:00        # 运行时间
```

### 环境设置
```bash
# 加载模块
module load python/3.8
module load cuda/11.8

# 激活环境
source activate neuralhydrology_gpu
```

## 📊 性能优化

### 多GPU训练
- 使用 `torch.nn.DataParallel` 或 `torch.nn.parallel.DistributedDataParallel`
- 调整批处理大小以充分利用GPU内存
- 使用混合精度训练减少内存使用

### 内存优化
- 使用梯度累积减少内存占用
- 启用内存映射文件读取
- 调整数据加载器的工作进程数

### I/O优化
- 使用SSD存储训练数据
- 启用数据预取
- 使用压缩数据格式

## 🔧 故障排除

### 常见问题

1. **GPU内存不足**
   - 减少批处理大小
   - 使用梯度累积
   - 启用混合精度训练

2. **作业超时**
   - 增加时间限制
   - 优化训练参数
   - 使用检查点恢复

3. **数据加载慢**
   - 使用SSD存储
   - 增加数据加载器工作进程
   - 启用数据预取

4. **网络问题**
   - 检查网络连接
   - 使用本地数据副本
   - 启用断点续传

## 📚 相关文档

- `docs/guides/GPU_SETUP_GUIDE.md` - GPU设置指南
- `docs/guides/GPU_TRAINING_README.md` - GPU训练说明
- `docs/technical/ROOT_FILES_ANALYSIS.md` - 文件分析报告

## ⚠️ 注意事项

1. **资源限制**: 注意HPC系统的资源限制和配额
2. **环境依赖**: 确保HPC环境已正确配置
3. **数据访问**: 确认数据文件在HPC系统上可访问
4. **权限管理**: 检查文件权限和访问控制

## 🔄 维护说明

- 定期更新HPC配置以适应系统变化
- 监控资源使用情况
- 优化作业调度策略
- 保持与HPC管理员的沟通
