# 📈 Project B: Full 531 Basins Benchmark

**状态**: 🚀 活跃 (Active)
**路径**: `runs/full_531_*`
**最后更新**: 2025-12-21

---

## 1. 任务目标
基于 CAMELS-US 数据集 (531 个流域)，建立大样本水文深度学习模型的性能基准 (Benchmark)，并对比不同架构 (LSTM, GRU, Transformer, etc.) 的表现。

## 2. 实验进度表

| 实验ID | 模型 | 状态 | Best Val NSE | Test NSE | 备注 |
|---|---|---|---|---|---|
| `reproduce_531_nse074` | **CUDA-LSTM** | ✅ 完成 | **0.735** | **0.725** | 基线确立，结果稳健 |
| `full_531_gru_ep30` | GRU | ✅ 完成 | 0.743 (Ep44) | **0.681** | 性能略逊于 LSTM，但差距不大 |
| `full_531_transformer` | Transformer | ✅ 完成 | 0.691 | - | 性能略逊，收敛较慢 |
| `full_531_ealstm` | EA-LSTM | ⚠️ 中断 | 0.732 | - | 潜力巨大，因 CPU 训练太慢中断 |
| `full_531_arlstm` | AR-LSTM | ⚠️ 中断 | 0.830* | - | *疑因 AR 泄露，需进一步验证 |
| `full_531_mtslstm` | MTS-LSTM | ❌ 不适用 | - | - | 需多频率数据，CAMELS-US 不支持 |
| `full_531_multihead` | Multihead | ✅ 完成 | 0.708 (Ep26) | **0.679** | 配置已修复，测试完成 |

## 3. 基线模型详细报告 (CUDA-LSTM)

### 3.1 训练过程
![Training Loss](results/fig1_training_loss.png)
> **分析**: 训练 Loss 持续下降，但验证 Loss 在 Epoch 10 后震荡，存在轻微过拟合。

### 3.2 测试集表现 (Test Set)
![Test Summary](results/fig9_test_summary.png)
*   **Median NSE**: **0.725**
*   **Good Performance (NSE>=0.7)**: 56.5% 的流域
*   **Poor Performance (NSE<0.5)**: 14.9% 的流域

### 3.3 空间分布
![Spatial Map](results/fig5_spatial_nse.png)
> **规律**: 东西两岸湿润区表现优异，中部干旱区表现较差。

### 3.4 区域对比
![Regional Boxplot](results/fig8_regional_boxplot.png)
> **Region 01 (New England)** 和 **Region 14 (Upper Colorado)** 表现最佳。

---

## 4. LSTM vs GRU 对比分析

### 4.1 性能对比表

| 指标 | CUDA-LSTM (基线) | GRU (Epoch 50) | 差值 |
|------|------------------|----------------|------|
| **Median NSE** | **0.725** | 0.681 | -0.044 ↓ |
| **Mean NSE** | 0.650 | 0.570 | -0.080 ↓ |
| **NSE >= 0.7** | **56.5%** | 45.0% | -11.5% ↓ |
| **NSE < 0.5** | 14.9% | 22.4% | +7.5% ↑ |
| **Best Val NSE** | 0.735 (Ep22) | **0.743** (Ep44) | +0.008 ↑ |

### 4.2 分析结论
- **GRU 性能略逊于 LSTM**：在测试集上，中位数 NSE 低 4.4%，良好表现流域少 11.5%
- **GRU 收敛更稳定**：验证集上 GRU 的最佳 NSE (0.743) 略高于 LSTM (0.735)
- **GRU 训练更高效**：相同参数下 GRU 通常比 LSTM 计算量更小
- **建议**：对于大样本基准测试，**LSTM 仍是更可靠的选择**

---

## 5. 配置修复记录 (2025-12-16)

### 5.1 MTS-LSTM 问题分析
**错误**: `ValueError: MTS-LSTM expects more than one input frequency`
**原因**: MTS-LSTM 设计用于多频率数据（如 1D + 1H），但 CAMELS-US 仅有日尺度数据
**状态**: ❌ 不适用于本项目
**解决方案**: 如需使用 MTS-LSTM，应切换到 CAMELS-H（小时级数据）

### 5.2 Multihead 配置修复
**错误**: `IndexError: list index out of range` (在 `InputLayer` 中)
**原因**: 缺少 `hindcast_inputs` 和 `forecast_inputs` 配置
**修复**: 添加以下配置项:

```yaml
dynamic_inputs:           # 数据加载所需
hindcast_inputs:          # 回顾期输入（历史观测）
forecast_inputs:          # 预报期输入（气象预报）
```

**状态**: ✅ 已修复，训练及测试完成

### 5.3 Multihead 测试结果 (2025-12-21)

| Epoch | Median NSE | Mean NSE | NSE≥0.7 | NSE<0.5 |
|-------|-----------|----------|---------|---------|
| 30 | 0.667 | 0.567 | 41.1% | 22.2% |
| **40** | **0.679** | 0.548 | **42.0%** | 19.8% |

**结论**: Multihead 模型性能略低于 CUDA-LSTM 和 GRU，但仍具备竞争力。

---

## 6. 后续计划
1.  ~~修复 MTS-LSTM 和 Multihead 模型的配置错误~~ ✅
2.  ~~等待 Multihead 训练完成并评估~~ ✅ (Test NSE=0.679)
3.  重新评估 AR-LSTM，确认是否保留自回归输入
4.  尝试其他架构（如 Attention-LSTM, Transformer 改进版）
5.  扩展到 Caravan 全球数据集（见 [数据使用指南](../../DATA_USAGE_GUIDE.md)）

---
[返回项目总览](../../PROJECTS_OVERVIEW.md)

