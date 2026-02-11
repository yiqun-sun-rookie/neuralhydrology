# 🐍 Mamba 小时级水文模型研究

**研究目标**: 将 Mamba (State Space Model) 应用于大规模小时级水文数据集，探索其在长序列建模和洪水峰值捕捉方面的优势

**状态**: 🚀 **活跃中** (Active Research)  
**创建日期**: 2026-01-09  
**最后更新**: 2026-01-09

---

## 📋 目录

1. [研究背景与动机](#研究背景与动机)
2. [研究目标与问题](#研究目标与问题)
3. [技术实现](#技术实现)
4. [实验配置](#实验配置)
5. [实验进展](#实验进展)
6. [结果记录](#结果记录)
7. [待完成任务](#待完成任务)
8. [技术细节](#技术细节)

---

## 🎯 研究背景与动机

### 研究意义

1. **新颖性**: Mamba (2023-2024) 是最新的深度学习架构，具有线性复杂度的长序列建模能力
2. **应用空白**: 目前**尚未有研究**在大规模小时级水文数据集上验证 Mamba 模型
3. **技术优势**: 
   - 相比 Transformer 的 O(n²) 复杂度，Mamba 为 O(n)
   - 相比 LSTM 的梯度消失问题，Mamba 能更好地捕捉长距离依赖
   - 特别适合小时级数据的长序列建模（seq_length = 3000+）

### 数据集选择

- **CAMELS-H (Hourly)**: 大规模小时级水文数据集
  - 455+ 个流域
  - 9 个动态气象输入变量
  - 13 个静态流域属性
  - 时间跨度: 2010-2020

### 对比基准

- **LSTM (CudaLSTM)**: 传统循环神经网络，作为基线模型
- **性能指标**: NSE (Nash-Sutcliffe Efficiency), KGE (Kling-Gupta Efficiency)

---

## 🔬 研究目标与问题

### 核心研究问题

1. **性能对比**: Mamba 在大规模小时级水文数据上的表现是否优于 LSTM？
2. **长序列优势**: Mamba 的长序列建模能力（seq_length = 3000+）是否有助于小时级预报？
3. **计算效率**: Mamba 的训练和推理效率如何？
4. **极端事件**: Mamba 在捕捉洪水峰值和快速响应过程方面是否更优？

### 论文发表目标

- **创新点**: 首个在大规模小时级水文数据集上验证 Mamba 模型的研究
- **贡献**: 
  - 验证 Mamba 在水文时间序列预测中的有效性
  - 提供 Mamba vs LSTM 的全面对比
  - 探索长序列建模对小时级预报的影响

---

## 🛠️ 技术实现

### 模型集成

**文件**: `neuralhydrology/modelzoo/mamba.py`

**关键特性**:
- ✅ 使用 Hugging Face `transformers` 后端（Windows 兼容）
- ✅ 适配连续型水文数据（通过 `InputLayer` + `inputs_embeds`）
- ✅ 支持多变量时间序列输入
- ✅ 集成到 NeuralHydrology 框架

**技术细节**:
```python
# 关键组件
- InputLayer: 处理动态和静态特征
- transition_layer: 映射到 Mamba 的 d_model 维度
- HF_MambaModel: Hugging Face transformers 实现
- RegressionHead: 输出层
```

### 配置参数支持

**文件**: `neuralhydrology/utils/config.py`

**新增参数**:
- `mamba_d_state`: 状态维度（默认 16）
- `mamba_d_conv`: 卷积核大小（默认 4）
- `mamba_expand`: 扩展因子（默认 2）
- `mamba_n_layers`: Mamba 层数（默认 2）

### Bug 修复

1. **Windows tqdm 兼容性** (`neuralhydrology/evaluation/tester.py`)
   - 问题: `OSError: [Errno 22] Invalid argument` 在验证阶段
   - 解决: 添加异常处理，使用 `file=None` 作为后备

2. **配置参数识别** (`neuralhydrology/utils/config.py`)
   - 问题: `ValueError: ['mamba_n_layers'] are not recognized config keys`
   - 解决: 添加 Mamba 参数到 Config 类

---

## ⚙️ 实验配置

### Mini Benchmark (50 Basins)

#### Mamba 配置
**文件**: `src/mamba_camelsh/configs/camelsh_mamba_mini.yml`

```yaml
experiment_name: camelsh_mamba_mini_benchmark
dataset: generic
data_dir: data/camelsh
train_basin_file: src/mamba_camelsh/data/test_50_basins.txt

# 时间划分
train_start_date: "01/01/2010"
train_end_date: "31/12/2014"
validation_start_date: "01/01/2015"
validation_end_date: "31/12/2017"
test_start_date: "01/01/2018"
test_end_date: "31/12/2020"

# 模型配置
model: mamba
hidden_size: 128
mamba_d_state: 16
mamba_d_conv: 4
mamba_expand: 2
mamba_n_layers: 2

# 训练配置
epochs: 10
batch_size: 16
seq_length: 168  # 7天小时数
optimizer: AdamW
loss: NSE
learning_rate: {0: 0.003, 5: 0.001}
device: cpu  # 或 cuda:0
```

#### LSTM 基线配置
**文件**: `src/mamba_camelsh/configs/camelsh_lstm_mini.yml`

```yaml
experiment_name: camelsh_lstm_mini_benchmark
model: cudalstm
hidden_size: 128
epochs: 10
batch_size: 128  # LSTM 可以更大
seq_length: 168
device: cuda:0
# 其他配置与 Mamba 相同
```

### 数据集配置

**动态输入** (9个):
- `Rainf`: 降雨
- `Tair`: 气温
- `SWdown`: 短波辐射
- `LWdown`: 长波辐射
- `Qair`: 比湿
- `PSurf`: 气压
- `Wind_E`, `Wind_N`: 风速分量
- `PotEvap`: 潜在蒸发

**静态属性** (13个):
- `elev_mean`, `slope_mean`, `area`
- `clay_frac`, `sand_frac`, `soil_porosity`, `permeability`
- `frac_forest`
- `p_mean`, `pet_mean`, `aridity`, `frac_snow`
- `high_prec_freq`

**目标变量**:
- `Streamflow`: 流量

---

## 📊 实验进展

### ✅ 已完成

| 任务 | 日期 | 状态 | 结果/备注 |
|------|------|------|----------|
| **Mamba 模型集成** | 2026-01-05 | ✅ 完成 | Hugging Face transformers 后端 |
| **CPU Tiny Test** | 2026-01-05 | ✅ 完成 | 50 basins, 1 epoch, NSE=0.149 |
| **Windows tqdm 修复** | 2026-01-09 | ✅ 完成 | 解决验证阶段崩溃问题 |
| **配置参数支持** | 2026-01-05 | ✅ 完成 | 添加所有 Mamba 超参数 |

### 🔄 进行中

| 任务 | 开始日期 | 状态 | 预计完成 |
|------|----------|------|----------|
| **LSTM Mini Benchmark** | - | ⏳ 待启动 | - |
| **Mamba Mini Benchmark** | - | ⏳ 待启动 | - |

### ⏸️ 已中断/待重启

| 任务 | 开始日期 | 中断原因 | 状态 |
|------|----------|----------|------|
| **Mamba Daily Benchmark** | 2026-01-05 | tqdm 错误（已修复） | 🔄 待重启 |
| | | Epoch 1 完成 (loss=0.03100) | |

---

## 📈 结果记录

### CPU Tiny Test (验证性测试)

**配置**:
- 50 basins
- 1 epoch
- `batch_size=4`, `seq_length=48`, `hidden_size=32`
- `mamba_n_layers=1`

**结果**:
- ✅ **NSE = 0.149** (技术路线验证通过)
- ✅ 模型可以正常运行
- ✅ 无技术障碍

**结论**: Mamba 模型集成成功，可以处理小时级水文数据。

### Mini Benchmark (待完成)

**计划对比指标**:
- NSE (Nash-Sutcliffe Efficiency)
- KGE (Kling-Gupta Efficiency)
- 训练时间对比
- 内存占用对比
- 峰值捕捉能力

**结果表格** (待填充):

| 模型 | NSE (Val) | KGE (Val) | NSE (Test) | KGE (Test) | 训练时间 | 备注 |
|------|-----------|-----------|------------|------------|----------|------|
| LSTM | - | - | - | - | - | 基线 |
| Mamba | - | - | - | - | - | 实验组 |

---

## 📝 待完成任务

### 短期任务 (1-2周)

- [ ] **完成 LSTM Mini Benchmark**
  - 配置文件: `src/mamba_camelsh/configs/camelsh_lstm_mini.yml`
  - 预期时间: 2-4 小时（GPU）
  
- [ ] **完成 Mamba Mini Benchmark**
  - 配置文件: `src/mamba_camelsh/configs/camelsh_mamba_mini.yml`
  - 预期时间: 8-12 小时（CPU）或 4-6 小时（GPU）
  
- [ ] **结果对比分析**
  - 生成对比图表
  - 分析性能差异
  - 评估长序列优势

### 中期任务 (1-2月)

- [ ] **扩展到全规模 CAMELS-H**
  - 455+ 个流域
  - 完整训练集
  
- [ ] **超长序列测试**
  - `seq_length = 3000+` (半年/一年小时数)
  - 验证 Mamba 的长序列优势
  
- [ ] **极端事件分析**
  - 洪水峰值捕捉能力
  - 快速响应过程建模

### 长期任务 (论文发表)

- [ ] **论文撰写**
  - 方法部分
  - 实验结果
  - 对比分析
  
- [ ] **代码开源准备**
  - 文档完善
  - 示例代码
  - 可复现性验证

---

## 🔧 技术细节

### 模型架构

```
Input (动态 + 静态特征)
    ↓
InputLayer (特征嵌入)
    ↓
transition_layer (映射到 hidden_size)
    ↓
Mamba Model (HF_MambaModel)
    ├─ d_state: 16
    ├─ d_conv: 4
    ├─ expand: 2
    └─ n_layers: 2
    ↓
Dropout (output_dropout: 0.1)
    ↓
RegressionHead
    ↓
Output (Streamflow)
```

### 关键代码位置

| 组件 | 文件路径 |
|------|----------|
| Mamba 模型实现 | `neuralhydrology/modelzoo/mamba.py` |
| 模型注册 | `neuralhydrology/modelzoo/__init__.py` |
| 配置支持 | `neuralhydrology/utils/config.py` |
| 验证器修复 | `neuralhydrology/evaluation/tester.py` |
| Mamba 配置 | `src/mamba_camelsh/configs/camelsh_mamba_*.yml` |
| LSTM 配置 | `src/mamba_camelsh/configs/camelsh_lstm_*.yml` |

### 环境要求

- **Python**: 3.8+
- **PyTorch**: 1.12+
- **transformers**: 4.39.0+ (Mamba 支持)
- **CUDA**: 可选（GPU 加速）

### 运行命令

```bash
# LSTM Mini Benchmark
python -m neuralhydrology.nh_run train --config-file src/mamba_camelsh/configs/camelsh_lstm_mini.yml

# Mamba Mini Benchmark
python -m neuralhydrology.nh_run train --config-file src/mamba_camelsh/configs/camelsh_mamba_mini.yml

# 评估
python -m neuralhydrology.nh_run evaluate --run-dir runs/camelsh_mamba_mini_benchmark_*
```

---

## 📚 参考文献

### Mamba 相关

- **Mamba 原始论文**: Gu, A., & Dao, T. (2023). Mamba: Linear-Time Sequence Modeling with Selective State Spaces. arXiv preprint arXiv:2312.00752.
- **Hugging Face 实现**: https://huggingface.co/docs/transformers/model_doc/mamba

### 水文模型相关

- **CAMELS-H**: Kratzert, F., et al. (2023). Caravan - A global dataset for large-sample hydrology. Scientific Data.
- **小时级水文建模**: Gauch, M., et al. (2021). Rainfall–runoff prediction at multiple timescales with a single Long Short-Term Memory network. Hydrology and Earth System Sciences.

---

## 🔗 相关链接

- [Project C 总体进展](./PROGRESS.md)
- [数据使用指南](../../DATA_USAGE_GUIDE.md)
- [项目总览](../../PROJECTS_OVERVIEW.md)

---

**最后更新**: 2026-01-09  
**维护者**: Research Team  
**状态**: 🚀 活跃研究

