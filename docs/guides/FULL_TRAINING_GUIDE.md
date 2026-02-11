# NeuralHydrology 完整数据集训练指南

本指南介绍如何使用新创建的完整数据集训练脚本进行674个流域的全面训练。

## 文件结构

```
├── scripts/
│   ├── full_train.py                       # 主训练脚本
│   ├── monitor_training.py                 # 训练监控脚本
│   └── training_recovery.py                # 训练恢复脚本
└── configs/full_training/
    ├── full_training.yml                   # 原始配置文件
    └── full_training_optimized.yml         # 优化配置文件
```

## 快速开始

### 1. 环境准备

确保已安装并激活 `neuralhydrology_gpu` conda环境：

```bash
conda activate neuralhydrology_gpu
```

**安装额外依赖（推荐）：**
```bash
# 安装psutil库以获得完整的系统监控功能
conda install psutil
# 或者使用pip
pip install psutil
```

**或者运行依赖安装脚本：**
- 双击 `install_dependencies.bat` 文件（Windows）
- 脚本会自动在 `neuralhydrology_gpu` 环境中安装必要依赖

### 2. 数据准备

确保CAMELS-US数据集已正确放置在 `data/CAMELS_US` 目录下，包含：
- `basin_dataset_lookup.pkl`
- `basin_timeseries.pkl`
- 各个流域的数据目录（如 `01013500/`）

### 3. 开始训练

#### 🎯 最简单的方式：交互式运行

在项目根目录打开终端（PowerShell、CMD 或 Bash），执行：

```bash
python scripts/full_train.py
```

脚本会自动启动交互式菜单，您只需要：
1. 选择操作（新训练/继续训练/监控等）
2. 输入GPU ID（默认0）
3. 选择是否启用监控模式
4. 确认开始训练

> 💡 Windows 用户也可以在资源管理器地址栏输入 `powershell` 或 `cmd` 打开终端，再运行上述命令。

**交互式菜单选项：**
- **选项1：开始新训练** - 使用完整数据集开始新的训练
- **选项2：继续训练** - 从之前的检查点恢复训练
- **选项3：监控训练进度** - 实时查看正在进行的训练状态
- **选项4：清理不完整的运行** - 删除失败的训练运行
- **选项5：生成训练报告** - 为完成的训练生成详细报告
- **选项6：退出** - 退出程序

#### 命令行方式

#### 方法一：使用Python脚本

```bash
# 新训练（使用优化配置）
python scripts/full_train.py --config configs/full_training/full_training_optimized.yml --gpu 0 --monitor --backup

# 继续训练
python scripts/full_train.py --resume --gpu 0 --monitor

# 清理不完整的运行
python scripts/full_train.py --clean
```

## 主要功能

### 1. 完整训练脚本 (`scripts/full_train.py`)

**新增功能：**
- 系统资源检查（CPU、内存、GPU）
- 数据可用性验证
- 实时资源监控
- 自动备份重要文件
- 增强的错误处理
- 训练进度确认

**使用方法：**
```bash
python scripts/full_train.py [选项]

选项：
  --config <path.yml>   指定配置文件
  --gpu <id|-1>         指定GPU ID，-1表示CPU
  --resume              继续训练
  --run-dir <path>      指定要恢复的训练目录
  --epoch <num>         指定从哪个epoch开始
  --monitor             启用详细监控
  --backup              训练前备份文件
  --clean               清理不完整运行
```

### 2. 训练监控 (`scripts/monitor_training.py`)

**功能：**
- 实时显示训练进度
- 系统资源监控
- GPU使用情况监控
- 训练状态检测
- 自动生成训练报告

**使用方法：**
```bash
# 监控最新训练
python scripts/monitor_training.py --verbose

# 监控指定训练
python scripts/monitor_training.py --run-dir runs/full_training_2025_1024_1631 --verbose

# 生成训练报告
python scripts/monitor_training.py --report
```

### 3. 训练恢复 (`scripts/training_recovery.py`)

**功能：**
- 自动检测训练异常
- 智能恢复失败训练
- 数据完整性验证
- 问题诊断和修复建议

**使用方法：**
```bash
# 检查所有训练状态
python scripts/training_recovery.py --check-all

# 诊断特定训练
python scripts/training_recovery.py --diagnose --run-dir runs/full_training_2025_1024_1631

# 自动恢复失败训练
python scripts/training_recovery.py --auto-recover

# 验证数据完整性
python scripts/training_recovery.py --verify-data
```

## 配置文件说明

### 优化配置 (`full_training_optimized.yml`)

相比原始配置的改进：

1. **模型参数优化：**
   - 隐藏层大小：128 → 256
   - Dropout：0.3 → 0.4
   - 训练轮数：50 → 100

2. **学习率调度优化：**
   - 更细致的学习率衰减策略
   - 添加最终学习率阶段

3. **训练参数优化：**
   - 批次大小：256 → 128（适应更多流域）
   - 验证频率：5 → 3（更频繁监控）
   - 验证流域数：50 → 100（更稳定估计）

4. **新增功能：**
   - 早停机制
   - 数据增强
   - 混合精度训练
   - 权重衰减正则化

## 监控和诊断

### 实时监控

训练过程中可以实时查看：
- 训练进度（当前epoch/总epochs）
- 训练和验证损失
- 最佳NSE指标
- CPU和内存使用率
- GPU内存使用情况

### 训练状态检查

系统会自动检测：
- 训练是否正常运行
- 是否出现错误或异常
- 日志文件是否正常更新
- 模型文件是否完整

### 自动恢复

当检测到训练异常时，系统可以：
- 自动从最新检查点恢复
- 清理临时文件释放空间
- 重新创建损坏的日志文件
- 提供修复建议

## 最佳实践

### 1. 训练前检查

```bash
# 检查环境
python scripts/full_train.py --config configs/full_training/full_training_optimized.yml --gpu 0 --backup

# 验证数据
python scripts/training_recovery.py --verify-data
```

### 2. 训练监控

```bash
# 启动训练（带监控）
python scripts/full_train.py --config configs/full_training/full_training_optimized.yml --gpu 0 --monitor

# 在另一个终端监控
python scripts/monitor_training.py --verbose
```

### 3. 定期检查

```bash
# 检查所有训练状态
python scripts/training_recovery.py --check-all

# 自动修复问题
python scripts/training_recovery.py --fix-issues
```

### 4. 训练完成后

```bash
# 生成训练报告
python scripts/monitor_training.py --report

# 检查最终结果
python scripts/training_recovery.py --diagnose --run-dir runs/[最新运行目录]
```

## 故障排除

### 常见问题

1. **ModuleNotFoundError: No module named 'psutil'**
   - 运行 `conda install psutil` 安装依赖
   - 或双击 `install_dependencies.bat` 自动安装
   - 脚本仍可运行，但系统监控功能会受限

2. **CUDA内存不足**
   - 减小batch_size
   - 使用CPU训练（--gpu -1）
   - 启用混合精度训练

3. **训练停滞**
   - 检查系统资源
   - 重启训练
   - 检查数据完整性

4. **数据路径错误**
   - 验证data_dir配置
   - 检查数据文件完整性
   - 重新下载数据

5. **环境问题**
   - 确认conda环境正确
   - 检查依赖包版本
   - 重新创建环境

6. **编码问题（Windows）**
   - 脚本已自动处理编码问题
   - 如果仍有问题，请确保使用UTF-8编码

### 获取帮助

```bash
# 查看脚本帮助
python scripts/full_train.py --help
python scripts/monitor_training.py --help
python scripts/training_recovery.py --help
```

## 性能优化建议

1. **硬件要求：**
   - 建议至少8GB GPU内存
   - 16GB以上系统内存
   - 足够的磁盘空间（至少50GB）

2. **训练优化：**
   - 使用SSD存储数据
   - 启用混合精度训练
   - 合理设置batch_size
   - 定期保存检查点

3. **监控优化：**
   - 启用详细监控模式
   - 定期检查训练状态
   - 及时处理异常情况

## 注意事项

1. **数据安全：**
   - 训练前自动备份配置文件
   - 定期检查数据完整性
   - 保留重要检查点

2. **资源管理：**
   - 监控系统资源使用
   - 避免同时运行多个训练
   - 及时清理临时文件

3. **版本控制：**
   - 使用Git跟踪配置变更
   - 记录实验参数和结果
   - 保持代码和配置同步

通过本指南，您应该能够成功运行完整数据集的训练，并获得良好的监控和恢复体验。
