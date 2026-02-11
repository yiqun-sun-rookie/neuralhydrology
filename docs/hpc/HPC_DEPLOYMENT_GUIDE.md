# NeuralHydrology HPC 部署指南

## 🎯 概述

本指南将帮助您在河海大学高性能计算平台(HPC)上部署和运行NeuralHydrology完整流域训练。通过本指南，您可以：

- 在HPC上配置训练环境
- 运行674个流域的大规模训练
- 监控训练进度和系统资源
- 管理训练作业和结果

## 📋 部署前准备

### 1. 环境要求
- 河海大学HPC账户
- 基本的Linux命令行操作知识
- 足够的计算资源配额（建议至少72小时GPU时间）

### 2. 数据准备
确保CAMELS_US数据集已上传到HPC系统：
```bash
# 数据目录结构
/data/neuralhydrology/CAMELS_US/
├── basin_dataset_lump_camels_us.txt
├── basin_metadata/
├── forcing/
└── streamflow/
```

### 3. 项目文件
确保NeuralHydrology项目文件已上传到HPC系统：
```bash
# 项目目录结构
/data/neuralhydrology/
├── neuralhydrology/          # 核心代码
├── configs/                  # 配置文件
├── scripts/                  # 脚本文件
├── slurm_jobs/              # SLURM作业脚本
└── data/                    # 数据目录
```

## 🚀 快速开始

### 方法1: 使用一键部署脚本（推荐）

```bash
# 1. 设置HPC环境
bash scripts/hpc_deploy.sh setup

# 2. 运行快速测试
bash scripts/hpc_deploy.sh test

# 3. 提交完整训练
bash scripts/hpc_deploy.sh train

# 4. 监控训练状态
bash scripts/hpc_deploy.sh monitor
```

### 方法2: 手动部署

#### 步骤1: 环境设置
```bash
# 进入项目目录
cd /data/neuralhydrology

# 运行环境设置脚本
bash scripts/setup_hpc_environment.sh
```

#### 步骤2: 快速测试
```bash
# 提交快速测试作业
sbatch slurm_jobs/hpc_quick_test.slurm

# 查看作业状态
squeue -u $USER

# 查看测试输出
tail -f logs/neuralhydrology_test_*.out
```

#### 步骤3: 完整训练
```bash
# 提交完整训练作业
sbatch slurm_jobs/hpc_full_training.slurm

# 监控训练进度
python scripts/monitor_training.py --project-dir /data/neuralhydrology
```

## 📁 文件结构说明

### 配置文件
```
configs/hpc/
├── hpc_full_training.yml     # 完整训练配置（674个流域，200个epoch）
├── hpc_quick_test.yml        # 快速测试配置（1个流域，5个epoch）
└── hpc_resume_training.yml   # 断点续训配置
```

### SLURM作业脚本
```
slurm_jobs/
├── hpc_full_training.slurm   # 完整训练作业（72小时，2个GPU）
├── hpc_quick_test.slurm      # 快速测试作业（30分钟，1个GPU）
└── hpc_resume_training.slurm # 断点续训作业
```

### 工具脚本
```
scripts/
├── setup_hpc_environment.sh  # 环境设置脚本
├── hpc_deploy.sh            # 一键部署脚本
├── monitor_training.py      # 训练监控脚本
└── backup_results.sh        # 结果备份脚本
```

## ⚙️ 配置说明

### HPC优化配置特点

#### 1. 模型配置优化
- **隐藏层大小**: 从128扩展到512
- **批次大小**: 从256提升到512
- **训练轮数**: 从50扩展到200

#### 2. 性能优化
- **混合精度训练**: 减少内存使用，提升速度
- **多GPU并行**: 支持2个GPU并行训练
- **数据预取**: 16个数据加载工作进程
- **内存优化**: 固定内存、持久化workers

#### 3. 资源申请
```bash
# 完整训练资源
--time=72:00:00          # 72小时
--gres=gpu:2             # 2个GPU
--mem=64G                # 64GB内存
--cpus-per-task=16       # 16个CPU核心

# 快速测试资源
--time=00:30:00          # 30分钟
--gres=gpu:1             # 1个GPU
--mem=16G                # 16GB内存
--cpus-per-task=4        # 4个CPU核心
```

## 📊 训练监控

### 实时监控
```bash
# 启动监控
python scripts/monitor_training.py --project-dir /data/neuralhydrology

# 单次状态检查
python scripts/monitor_training.py --once
```

### 监控指标
- **SLURM作业状态**: 作业ID、状态、运行时间
- **GPU使用情况**: 内存使用、利用率、温度
- **系统资源**: CPU负载、内存使用
- **训练进度**: 当前epoch、损失值、验证指标

### 日志查看
```bash
# 查看作业输出
tail -f logs/neuralhydrology_full_*.out

# 查看训练日志
tail -f runs/*/output.log

# 查看错误日志
tail -f logs/neuralhydrology_full_*.err
```

## 🔧 常用命令

### 作业管理
```bash
# 查看作业状态
squeue -u $USER

# 查看作业详情
scontrol show job <job_id>

# 取消作业
scancel <job_id>

# 取消所有作业
scancel -u $USER
```

### 系统监控
```bash
# 查看GPU状态
nvidia-smi

# 查看系统负载
htop

# 查看磁盘使用
df -h

# 查看内存使用
free -h
```

### 训练管理
```bash
# 查看训练结果
ls -la runs/

# 查看最新运行
ls -t runs/ | head -1

# 查看模型文件
ls -la runs/*/model_*.pt

# 备份结果
bash scripts/backup_results.sh
```

## 🚨 故障排除

### 常见问题及解决方案

#### 1. 作业提交失败
```bash
# 检查SLURM配置
scontrol show partition gpu

# 检查资源可用性
sinfo -p gpu

# 检查账户配额
sacctmgr show user $USER
```

#### 2. GPU内存不足
- 减少批次大小（batch_size: 512 → 256）
- 启用梯度累积
- 使用混合精度训练

#### 3. 训练中断
```bash
# 查看错误日志
tail -f logs/neuralhydrology_*.err

# 检查断点续训
python simple_train.py --resume

# 从指定epoch恢复
python simple_train.py --resume --run-dir runs/latest_run --epoch 50
```

#### 4. 数据加载慢
- 检查数据路径是否正确
- 使用SSD存储
- 增加数据预取工作进程

#### 5. 环境问题
```bash
# 重新激活环境
conda activate neuralhydrology_gpu

# 重新安装依赖
pip install -r requirements-gpu.txt

# 检查CUDA版本
nvcc --version
nvidia-smi
```

## 📈 性能优化建议

### 1. 资源优化
- 根据实际需求调整GPU数量和内存大小
- 合理设置训练时间限制
- 使用合适的CPU核心数

### 2. 训练优化
- 监控GPU利用率，确保>85%
- 调整批次大小以充分利用GPU内存
- 使用混合精度训练提升速度

### 3. 存储优化
- 使用高速存储（SSD）存放训练数据
- 定期清理临时文件
- 压缩存储训练结果

## 📝 最佳实践

### 1. 训练前检查
- 运行快速测试验证环境
- 检查数据完整性
- 确认资源配额充足

### 2. 训练中监控
- 定期检查训练进度
- 监控系统资源使用
- 及时处理异常情况

### 3. 训练后管理
- 及时备份训练结果
- 分析训练指标
- 清理临时文件

## 🎯 预期结果

### 训练性能
- **训练时间**: 预计48-72小时
- **模型性能**: NSE > 0.6 (目标)
- **收敛性**: 200个epoch内收敛

### 资源使用
- **GPU利用率**: >85%
- **内存使用**: <80%
- **存储需求**: ~50GB

## 📞 技术支持

### 获取帮助
1. 查看HPC用户手册
2. 联系HPC管理员
3. 查看项目文档
4. 检查错误日志

### 联系方式
- HPC技术支持: [HPC管理员邮箱]
- 项目问题: [项目维护者邮箱]

---

**注意**: 本指南基于河海大学HPC平台编写，其他HPC平台可能需要相应调整。建议在正式部署前与HPC管理员确认系统配置和要求。


