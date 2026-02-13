# Mamba 模型在 CAMELS-US 日尺度数据集上的实验记录

**项目启动日期**: 2025-12-29  
**最后更新**: 2026-01-09  
**状态**: 代码通路已验证（Mini Benchmark 成功），已迁移到 HPC 准备全量训练

---

## 📋 项目概述

### 研究目标
在标准 **CAMELS-US 日尺度数据集（531 个流域）** 上验证 Mamba 模型性能，与成熟的 LSTM 基准（NSE ~0.74）进行公平对比，证明 Mamba 在标准水文任务上是否达到或超过 State-of-the-Art。

### 研究背景
- ✅ **已完成**: Mamba 模型集成（基于 Hugging Face transformers 后端）
- ✅ **已完成**: 在 CAMELS-H 小时级数据上通过初步测试（50 个流域）
- 🎯 **当前目标**: 在标准 CAMELS-US 日尺度数据集上验证，与 LSTM 基准对比

---

## 🏗️ 技术实现

### 代码文件
- **模型实现**: `neuralhydrology/modelzoo/mamba.py`
  - 支持 Hugging Face transformers 后端（Windows 友好）
  - 支持官方 mamba_ssm 后端（需要 CUDA 编译，速度更快）
  - 自动选择可用后端（优先级：mamba_ssm > transformers）

- **配置支持**: `neuralhydrology/utils/config.py`
  - 已添加 Mamba 相关配置属性：
    - `mamba_d_state`: SSM 状态扩展因子（默认: 16）
    - `mamba_d_conv`: 局部卷积宽度（默认: 4）
    - `mamba_expand`: 块扩展因子（默认: 2）
    - `mamba_n_layers`: Mamba 层数（默认: 2，仅 HF 后端）

### 模型架构
- **基础架构**: Mamba State Space Model (SSM)
- **后端**: Hugging Face transformers（当前）
- **隐藏层大小**: 128
- **序列长度**: 365 天（1 年）
- **预测头**: Regression head

---

## 📁 实验配置

### 1. 全量实验配置（531 流域）
**文件**: `src/mamba_camels_us/configs/mamba_daily.yml`

**关键参数**:
- **数据集**: CAMELS-US Daily
- **流域数量**: 531
- **训练期**: 1999-10-01 至 2008-09-30（9 年）
- **验证期**: 1980-10-01 至 1989-09-30（9 年）
- **测试期**: 1989-10-01 至 1999-09-30（10 年）
- **Epochs**: 30
- **Batch Size**: 64（已从 128 降低以避免内存问题）
- **序列长度**: 365 天
- **学习率**: 0.001 → 0.0005 (epoch 10) → 0.0001 (epoch 20)
- **保存策略**: 每 10 个 epoch 保存一次

**数据文件**: `src/mamba_camels_us/data/531_basin_list.txt`

### 2. Mini Benchmark（50 流域）
**文件**: `src/mamba_camels_us/configs/mamba_daily_mini.yml`

**用途**: 快速验证代码通路  
**结果**: ✅ 成功完成 2 个 epoch，验证 NSE 0.39634

### 3. 快速验证配置（100 流域）
**文件**: `src/mamba_camels_us/configs/mamba_daily_quick.yml`

**用途**: 快速验证性能趋势（推荐使用）  
**参数**: 100 流域，5 epochs，2 年训练数据

---

## 📊 实验结果

### Mini Benchmark（50 流域，2 epochs）

| Epoch | 训练损失 | 验证损失 | 验证 NSE (中位数) |
|-------|----------|----------|-------------------|
| 1     | 0.08920  | 0.07231  | 0.39634           |
| 2     | 0.05148  | -        | -                 |

**结论**: ✅ Mamba 模型可以正常运行，代码无 Bug

**运行目录**: `runs/mamba_daily_mini_2026_0103_1750_ep2`

### 全量训练（531 流域，30 epochs）

| 指标 | 值 |
|------|-----|
| **状态** | ⚠️ 部分完成（第一个 epoch 完成，验证失败） |
| **Epoch 1 训练损失** | 0.03100 |
| **训练时长** | ~96 小时（4 天） |
| **验证结果** | ❌ 未生成（验证阶段失败） |
| **模型检查点** | ❌ 无（配置为每 10 个 epoch 保存） |

**运行目录**: `runs/mamba_daily_benchmark_2026_0105_2150_ep30`

**问题**: 
- 验证阶段 tqdm Windows 兼容性错误导致中断
- 训练速度极慢（每个 epoch 需要 4+ 天）

---

## ⚠️ 遇到的问题

### 1. 训练速度问题（严重）

**问题描述**:
- Hugging Face Mamba 使用 sequential implementation（无 CUDA kernel）
- 每个 epoch 需要 4+ 天（531 流域 × 9 年数据）
- 30 epochs 预计需要 120+ 天

**影响**:
- 全量实验不可行（时间成本过高）
- 需要优化方案

**解决方案**:
1. **安装 mamba-ssm CUDA kernel**（推荐，但 Windows 上需要编译）
   ```bash
   pip install mamba-ssm causal-conv1d>=1.1.0
   ```
   - 速度可提升 10-50 倍
   - Windows 上需要 CUDA 编译环境

2. **使用快速验证配置**（当前推荐）
   - 100 流域，5 epochs
   - 预计 1-2 天完成
   - 可以快速验证性能趋势

### 2. Windows 兼容性问题

**问题描述**:
- 验证阶段 tqdm 报错：`OSError: [Errno 22] Invalid argument`
- 导致训练完成但验证失败

**错误信息**:
```
File "C:\Users\yiqun\anaconda3\Lib\site-packages\tqdm\std.py", line 448, in status_printer
    getattr(sys.stderr, 'flush', lambda: None)()
OSError: [Errno 22] Invalid argument
```

**解决方案**:
- 修复 tqdm 兼容性（需要修改代码）
- 或禁用验证阶段的进度条

### 3. 检查点保存策略

**问题**:
- 配置为每 10 个 epoch 保存一次
- 第一个 epoch 完成后未保存检查点
- 如果训练中断，无法恢复

**建议**:
- 修改为每个 epoch 保存（至少前几个 epoch）
- 或使用 `save_weights_every: 1`

---

## 🎯 下一步计划

### 短期目标（1-2 周）

1. **运行快速验证实验**
   - 使用 `mamba_daily_quick.yml`（100 流域，5 epochs）
   - 预计 1-2 天完成
   - 目标：快速验证 Mamba 性能趋势

2. **修复 Windows 兼容性问题**
   - 修复 tqdm 错误
   - 确保验证阶段正常运行

3. **调整保存策略**
   - 修改配置为每个 epoch 保存检查点
   - 确保训练结果可恢复

### 中期目标（1-2 个月）

1. **性能优化**
   - 尝试安装 `mamba-ssm` CUDA kernel（如果可行）
   - 或使用其他加速方案

2. **完整对比实验**
   - 完成 Mamba 全量训练（531 流域，30 epochs）
   - 运行相同配置的 LSTM 基准
   - 对比 NSE、KGE 等指标

### 长期目标（3-6 个月）

1. **性能分析**
   - 分析 Mamba 在不同流域类型上的表现
   - 研究 Mamba 在长序列上的优势（seq_length > 365）

2. **论文/报告撰写**
   - 整理实验结果
   - 撰写技术报告或论文

---

## 📈 关键指标对比目标

| 模型 | 数据集 | 预期 NSE | 当前状态 |
|------|--------|----------|----------|
| **LSTM Baseline** | CAMELS-US (531) | ~0.74 | ✅ 已有基准 |
| **Mamba (目标)** | CAMELS-US (531) | ≥0.74 | 🔄 进行中 |

**当前最佳结果**:
- Mini Benchmark (50 流域): NSE 0.39634
- 全量训练 Epoch 1: 训练损失 0.03100（验证未完成）

---

## 📝 关键文件路径

### 配置文件
- `src/mamba_camels_us/configs/mamba_daily.yml` - 全量实验配置
- `src/mamba_camels_us/configs/mamba_daily_mini.yml` - Mini Benchmark 配置
- `src/mamba_camels_us/configs/mamba_daily_quick.yml` - 快速验证配置

### 数据文件
- `src/mamba_camels_us/data/531_basin_list.txt` - 531 个流域列表
- `src/mamba_camels_us/data/100_basin_list.txt` - 100 个流域列表
- `src/mamba_camels_us/data/50_basin_list.txt` - 50 个流域列表

### 运行结果
- `runs/mamba_daily_mini_2026_0103_1750_ep2/` - Mini Benchmark 结果
- `runs/mamba_daily_benchmark_2026_0105_2150_ep30/` - 全量训练结果（部分完成）

### 代码文件
- `neuralhydrology/modelzoo/mamba.py` - Mamba 模型实现
- `neuralhydrology/utils/config.py` - 配置支持

---

## 🔧 运行命令

### HPC 环境（推荐）

#### 1. 安装 mamba-ssm CUDA kernel（加速 10-50 倍）
```bash
# 加载 CUDA 模块
module load cuda/11.8  # 根据你的 HPC 调整版本

# 激活 conda 环境
conda activate neuralhydrology_gpu

# 运行安装脚本
bash hpc/install_mamba_ssm.sh
```

#### 2. 提交 SLURM 作业

**快速验证（推荐先运行）**:
```bash
sbatch src/mamba_camels_us/hpc/submit_mamba_quick.slurm
```

**全量训练**:
```bash
sbatch src/mamba_camels_us/hpc/submit_mamba_camels_us.slurm
```

**监控作业**:
```bash
# 查看作业状态
squeue -u $USER

# 查看实时日志
tail -f logs/mamba_camels_us_<job_id>.out

# 取消作业
scancel <job_id>
```

### 本地环境（Windows/Linux）

```bash
# 全量实验（531 流域，30 epochs）
nh-run train --config-file src/mamba_camels_us/configs/mamba_daily.yml

# 快速验证（100 流域，5 epochs，推荐）
nh-run train --config-file src/mamba_camels_us/configs/mamba_daily_quick.yml

# Mini Benchmark（50 流域，2 epochs）
nh-run train --config-file src/mamba_camels_us/configs/mamba_daily_mini.yml
```

### 监控训练
```bash
# 查看 GPU 状态
nvidia-smi

# 查看训练日志（Linux）
tail -f runs/mamba_daily_benchmark_*/output.log

# 使用 TensorBoard 查看训练曲线
tensorboard --logdir runs/mamba_daily_benchmark_*
```

---

## 📚 参考资料

### Mamba 相关
- [Mamba 论文](https://arxiv.org/abs/2312.00752)
- [Hugging Face Mamba](https://huggingface.co/docs/transformers/model_doc/mamba)
- [mamba-ssm GitHub](https://github.com/state-spaces/mamba)

### CAMELS-US 数据集
- [CAMELS 数据集官网](https://ral.ucar.edu/solutions/products/camels)
- NeuralHydrology 文档中的 CAMELS-US 使用指南

### 基准结果
- LSTM Baseline: NSE ~0.74（CAMELS-US 531 流域，日尺度）

---

## 📌 重要备注

1. **速度问题**: 当前使用 Hugging Face Mamba sequential implementation，速度很慢。建议安装 `mamba-ssm` CUDA kernel 以加速。

2. **Windows 兼容性**: 验证阶段存在 tqdm 兼容性问题，需要修复。

3. **保存策略**: 建议修改为每个 epoch 保存检查点，避免训练中断导致结果丢失。

4. **快速验证**: 推荐先运行快速验证配置（100 流域，5 epochs），快速验证性能趋势后再决定是否进行全量训练。

---

## 🔄 更新日志

- **2026-01-09**: 
  - 项目迁移到 HPC
  - 创建 HPC 专用 SLURM 脚本
  - 添加 mamba-ssm 安装指南
  - 代码通路已验证（Mini Benchmark 成功）
- **2026-01-09**: 全量训练第一个 epoch 完成，但验证阶段失败（Windows tqdm 问题）
- **2026-01-05**: 启动全量训练（531 流域，30 epochs）
- **2026-01-03**: Mini Benchmark 成功完成（50 流域，2 epochs）
- **2025-12-29**: 创建实验配置和文档

---

**维护者**: 水文深度学习团队  
**最后检查**: 2026-01-09
