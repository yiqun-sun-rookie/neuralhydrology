# ⏱️ Project C: Camelsh Hourly 实验

**状态**: 🚀 活跃 (Active)
**路径**: `runs/camelsh_*`
**最后更新**: 2026-01-09

---

## 📋 快速导航

- **[Mamba 小时级研究](./MAMBA_RESEARCH.md)**: 🐍 最新的 Mamba 模型研究（2026-01-09 启动）
- **本文档**: 总体项目进展和 LSTM 基线实验记录

---

## 1. 任务目标
探索 **小时级 (Hourly)** 时间分辨率下的大样本水文模拟能力。相比日尺度，小时级模拟对捕捉洪水峰值和快速响应过程更为关键。

**当前重点**: 
- ✅ LSTM 基线实验（已完成）
- 🚀 **Mamba 模型研究**（进行中，详见 [MAMBA_RESEARCH.md](./MAMBA_RESEARCH.md)）

## 2. 实验记录

### LSTM 基线实验

| 实验ID | 日期 | 模型 | 规模 | 配置特点 | 状态 |
|---|---|---|---|---|---|
| `camelsh_v2_more_data` | 12-04 | CUDA-LSTM | 455 Basins | `seq_len=336` (14天), 9个动态变量 | ✅ 完成 |
| `camelsh_hourly_opt` | 11-30 | - | - | 早期优化尝试 | ✅ 完成 |
| `camelsh_lstm_mini_benchmark` | 2026-01 | CUDA-LSTM | 50 Basins | `seq_len=168` (7天), Mini Benchmark | ⏳ 待运行 |

### Mamba 模型实验

| 实验ID | 日期 | 模型 | 规模 | 配置特点 | 状态 |
|---|---|---|---|---|---|
| `camelsh_mamba_mini_benchmark` | 2026-01 | Mamba | 50 Basins | `seq_len=168` (7天), Mini Benchmark | ⏳ 待运行 |
| `camelsh_mamba_tiny` | 2026-01 | Mamba | 50 Basins | 验证性测试 (1 epoch) | ✅ 完成 (NSE=0.149) |

**详细记录**: 参见 [MAMBA_RESEARCH.md](./MAMBA_RESEARCH.md)

## 3. 关键配置细节
*   **输入特征**: 
    *   `Rainf`: 降雨
    *   `Tair`: 气温
    *   `SWdown`: 短波辐射
    *   `LWdown`: 长波辐射
    *   `Qair`: 比湿
    *   `PSurf`: 气压
    *   `Wind_E`, `Wind_N`: 风速分量
*   **序列长度**: 336 (14天)
*   **Loss**: NSE, KGE

## 4. 当前挑战
*   **计算量大**: 小时级数据的数据点是日级的 24 倍，训练时间显著增加。
*   **数据缺失**: 部分流域小时级数据不完整，需进行筛选。

---
[返回项目总览](../../PROJECTS_OVERVIEW.md)

