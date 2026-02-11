# NeuralHydrology 完整流域训练 HPC 部署计划

## 📋 项目概述

### 当前状态分析
- **数据集**: CAMELS_US (674个流域)
- **模型**: CudaLSTM (隐藏层128，可扩展到512)
- **训练配置**: 50个epoch，批次大小256
- **数据分割**: 训练集(1980-1999) + 验证集(2000-2007) + 测试集(2008-2014)
- **目标**: 在河海大学HPC平台上进行大规模训练

### HPC部署目标
1. **扩展训练规模**: 从50个epoch扩展到200个epoch
2. **优化模型容量**: 隐藏层从128扩展到512
3. **提高训练效率**: 利用HPC的GPU集群和并行计算
4. **确保稳定性**: 实现断点续训和错误恢复

## 🏗️ 部署架构

### 1. 环境准备
```bash
# HPC环境要求
- Python 3.10
- CUDA 11.8
- PyTorch 2.0+
- SLURM作业调度系统
- 32GB+ 内存
- 1-4个GPU
```

### 2. 数据准备
```bash
# 数据目录结构
/data/neuralhydrology/
├── CAMELS_US/           # 原始数据
├── processed/           # 预处理数据
├── configs/            # 配置文件
└── runs/               # 训练输出
```

### 3. 配置优化策略

#### 3.1 模型配置优化
- **隐藏层大小**: 128 → 512 (提升模型容量)
- **批次大小**: 256 → 512 (充分利用GPU内存)
- **序列长度**: 保持365天
- **学习率调度**: 更细粒度的调度策略

#### 3.2 训练配置优化
- **训练轮数**: 50 → 200 (充分利用HPC资源)
- **验证频率**: 每5个epoch → 每10个epoch
- **保存频率**: 每10个epoch → 每20个epoch
- **工作进程**: 0 → 16 (HPC多核优势)

#### 3.3 性能优化
- **混合精度训练**: 减少内存使用，提升速度
- **数据预取**: 优化数据加载
- **梯度累积**: 支持更大有效批次
- **内存映射**: 优化大数据集访问

## 📁 文件结构规划

```
hpc_deployment/
├── configs/
│   ├── hpc_full_training.yml      # HPC优化配置
│   ├── hpc_quick_test.yml         # 快速测试配置
│   └── hpc_resume_training.yml    # 断点续训配置
├── scripts/
│   ├── setup_hpc_environment.sh   # 环境设置脚本
│   ├── submit_training_job.sh     # 作业提交脚本
│   ├── monitor_training.py        # 训练监控脚本
│   └── backup_results.sh          # 结果备份脚本
├── slurm_jobs/
│   ├── full_training.slurm        # 完整训练作业
│   ├── quick_test.slurm           # 快速测试作业
│   └── resume_training.slurm      # 续训作业
└── utils/
    ├── hpc_config_generator.py    # 配置生成器
    ├── performance_monitor.py     # 性能监控
    └── result_analyzer.py         # 结果分析
```

## 🚀 实施步骤

### 阶段1: 环境准备 (1-2天)
1. **HPC环境检查**
   - 验证CUDA版本和GPU可用性
   - 检查Python环境和依赖包
   - 确认数据访问权限

2. **环境配置**
   - 创建conda环境
   - 安装依赖包
   - 配置环境变量

### 阶段2: 配置优化 (1天)
1. **生成HPC优化配置**
   - 调整模型参数
   - 优化训练设置
   - 配置性能参数

2. **创建作业脚本**
   - SLURM作业配置
   - 资源申请设置
   - 错误处理机制

### 阶段3: 测试验证 (1-2天)
1. **快速测试**
   - 小规模数据集测试
   - 验证环境配置
   - 检查输出格式

2. **性能基准测试**
   - 测量训练速度
   - 监控资源使用
   - 优化参数设置

### 阶段4: 正式训练 (3-7天)
1. **提交训练作业**
   - 使用优化配置
   - 监控训练进度
   - 处理异常情况

2. **结果管理**
   - 定期备份结果
   - 分析训练指标
   - 生成报告

## ⚙️ 关键配置文件

### HPC优化训练配置
```yaml
# 基础设置
experiment_name: hpc_full_674_basins_optimized
dataset: camels_us
data_dir: /data/neuralhydrology/CAMELS_US

# 模型配置 - HPC优化
model: cudalstm
head: regression
hidden_size: 512              # 从128提升到512
initial_forget_bias: 3
output_dropout: 0.2
output_activation: linear

# 训练配置 - HPC优化
epochs: 200                   # 从50提升到200
batch_size: 512              # 从256提升到512
optimizer: AdamW
loss: NSE

# 学习率调度 - 更细粒度
learning_rate:
  0: 0.001
  50: 0.0008
  100: 0.0005
  150: 0.0003
  180: 0.0001

# 性能优化
num_workers: 16              # HPC多核优势
validate_every: 10           # 减少验证频率
save_weights_every: 20       # 减少保存频率
use_mixed_precision: true    # 混合精度训练
pin_memory: true            # 固定内存
```

### SLURM作业配置
```bash
#!/bin/bash
#SBATCH --job-name=neuralhydrology_full
#SBATCH --output=logs/neuralhydrology_%j.out
#SBATCH --error=logs/neuralhydrology_%j.err
#SBATCH --time=72:00:00      # 72小时训练时间
#SBATCH --partition=gpu      # GPU分区
#SBATCH --gres=gpu:2         # 申请2个GPU
#SBATCH --mem=64G            # 64GB内存
#SBATCH --cpus-per-task=16   # 16个CPU核心
#SBATCH --nodes=1            # 单节点
```

## 📊 预期性能提升

### 训练效率
- **训练速度**: 预计提升3-5倍
- **内存使用**: 通过混合精度优化减少30%
- **GPU利用率**: 从60%提升到90%+

### 模型性能
- **模型容量**: 隐藏层从128扩展到512
- **训练深度**: 从50个epoch扩展到200个epoch
- **收敛质量**: 更长时间训练获得更好收敛

### 资源利用
- **并行处理**: 16个CPU核心并行数据加载
- **GPU集群**: 多GPU并行训练
- **存储优化**: 高效的数据访问模式

## 🔧 故障排除预案

### 常见问题及解决方案

1. **GPU内存不足**
   - 减少批次大小
   - 启用梯度累积
   - 使用混合精度训练

2. **训练中断**
   - 自动断点续训
   - 定期保存检查点
   - 错误恢复机制

3. **数据加载慢**
   - 使用SSD存储
   - 增加数据预取
   - 优化数据格式

4. **作业超时**
   - 增加时间限制
   - 优化训练参数
   - 分阶段训练

## 📈 监控和评估

### 实时监控指标
- GPU使用率和温度
- 内存使用情况
- 训练损失和验证指标
- 数据加载速度

### 定期评估
- 每10个epoch评估模型性能
- 监控过拟合情况
- 调整学习率策略
- 备份重要检查点

## 🎯 成功标准

### 技术指标
- [ ] 成功在HPC上运行200个epoch
- [ ] 模型收敛到满意的NSE指标
- [ ] 训练时间控制在72小时内
- [ ] 无重大错误或中断

### 性能指标
- [ ] GPU利用率 > 85%
- [ ] 内存使用 < 80%
- [ ] 训练速度 > 本地3倍
- [ ] 模型性能提升 > 10%

## 📝 后续计划

### 短期目标 (1-2周)
1. 完成HPC环境部署
2. 成功运行完整训练
3. 获得初步结果

### 中期目标 (1个月)
1. 优化训练参数
2. 扩展实验规模
3. 分析结果质量

### 长期目标 (3个月)
1. 发表研究成果
2. 建立标准流程
3. 推广到其他项目

---

**注意**: 此计划需要根据河海大学HPC平台的具体配置和要求进行调整。建议在正式部署前与HPC管理员确认资源配额和系统限制。


