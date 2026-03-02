# 04 - Nam Ou Kuwei Hourly Forecasting (No-Leak Reproduction)

**状态**: done (主线结论已固化，按需重启)  
**创建日期**: 2025-10-01  
**最后更新**: 2026-03-02

---

## 1. 原始主线与当前定位

本课题的原始主线是：

1. 在严格 no-leak 约束下复现 Nam Ou Kuwei 小时级预报结果。  
2. 对比不同 DL 架构在相同预算下的公平表现。  
3. 明确哪些增益来自输入信息（尤其历史流量），哪些来自架构本身。

当前结论是：

- 有历史流量滞后输入时（`qobs_shift{lead}`），模型可达到高精度。  
- 去掉流量输入后（rain-only），所有模型性能显著下降。  
- “窗口加长是否有益”是 lead-dependent 现象，不是统一规律。

---

## 2. 任务边界与目录

| 类型 | 路径 | 说明 |
| :--- | :--- | :--- |
| Code | `src/namou_kuwei/` | 配置、脚本、说明 |
| Results | `results/04_namou_kuwei/` | 训练与评估输出 |
| Logs | `logs/04_namou_kuwei/` | 日志目录 |
| Idea Doc | `draft/ideas/04_namou_kuwei.md` | 本文档 |

---

## 3. 数据划分与 no-leak 定义

统一时间切分：

- Train: 2020-01-01 to 2021-06-30  
- Validation: 2021-07-01 to 2021-12-31  
- Test: 2022-01-01 to 2022-12-31

no-leak 约束：

1. 不使用任何未来实测流量。  
2. L7 使用 `qobs_shift{lead}`（过去流量，允许）。  
3. L8 完全去除流量输入（不含 `qobs_shift*`、不含 `autoregressive_inputs`）。  
4. L8 用 `p_*_shift{lead}` 保证 leadtime 定义一致。

---

## 4. 实验层级（当前有效）

| Level | 目录 | 说明 |
| :--- | :--- | :--- |
| L7 | `src/namou_kuwei/configs/no_leak/07_model_fair/` | 公平多模型对比（Rain + `qobs_shift{lead}` + Static） |
| L8 | `src/namou_kuwei/configs/no_leak/08_model_fair_rain_only/` | 公平多模型对比（Rain-only + Static） |

---

## 5. 关键结果（已完成）

### 5.1 L7（含流量滞后输入）

来源：`results/04_namou_kuwei/L7_fair_all_models_LT1_6_12_24_summary.csv`

结论摘要：

- 整体性能高，GRU 在多数 lead 上最强。  
- 最高结果出现在 LT1 GRU，NSE 约 `0.996`。  
- 这说明历史流量滞后信息是极强信号。

### 5.2 L8（去流量，仅降雨+静态）

来源：`results/04_namou_kuwei/L8_rainonly_current_status.csv`

截至 2026-03-02：

- 已有完整测试：GRU/CudaLSTM/EALSTM/Transformer 全 lead，Mamba 到 LT1/LT6。  
- 2026-03-02 决策：`Mamba LT12/LT24` 不再补跑，按主线归档处理。  
- 整体 NSE 为负，显著弱于 L7。  
- 当前 rain-only 条件下，GRU 仍是最优或近最优。

---

## 6. 窗口实验（GRU, L8）

### 6.1 四个 lead 的 `seq168 vs seq336`

来源：`results/04_namou_kuwei/L8_window_test_gru_all_leads_seq168_vs336.csv`

| Lead | NSE(seq168) | NSE(seq336) | 差值(336-168) |
| :--- | ---: | ---: | ---: |
| LT1 | -0.1706 | -0.2636 | -0.0930 |
| LT6 | -0.1666 | -0.2551 | -0.0885 |
| LT12 | -0.1886 | -0.1551 | +0.0336 |
| LT24 | -0.1166 | +0.1203 | +0.2369 |

图：`results/04_namou_kuwei/L8_window_test_gru_all_leads_nse_seq168_vs336.png`

### 6.2 “是否是训练后期过拟合”核查

对 LT1/6/12 使用各自最佳验证 epoch 再测 test，结果仍未超过 seq168 基线。  
来源：`results/04_namou_kuwei/L8_window_test_gru_short_leads_best_epoch_vs_seq168.csv`

结论：

- “长窗口一定更好”不成立。  
- 更准确表述是：**窗口长度与 lead 强耦合（lead-dependent memory）**。

---

## 7. 已证实与未证实（避免过度解释）

已证实：

1. 输入历史流量滞后（L7）可显著提升效果。  
2. rain-only 场景下，性能明显下降。  
3. 窗口长度的收益是 lead-dependent，不可一刀切。

未证实（仅为假设）：

1. “主要问题一定是初始状态误差”。  
2. “DA/DI 一定优于单纯窗口调整”。  
3. “Mamba 在该场景最终一定优于 GRU”。

---

## 8. 归档项（已决策）

L8 Mamba 仍留空：

- LT12  
- LT24

决策（2026-03-02）：以上两项标记为归档跳过（`archived_skip_20260302`），当前阶段不再执行补跑。  
说明：该处理不会改变当前“主方向判断”（输入信息增益与 lead-dependent memory 的核心事实），仅保留附表空项。

---

## 9. 归档后的下一步建议（若重启）

1. 若需要论文附表完整，再单独重启 `L8 Mamba LT12/LT24` 补跑。  
2. 若关注可用性能，优先做按 lead 的窗口小网格搜索（如 168/240/336）。  
3. 若继续方法创新，再做 DI/DA 对照实验，但必须明确 no-leak 边界。  
4. 所有“机制性结论”都必须基于对照实验，不基于单次现象。

---

## 10. 旁线想法归档：Lead 自适应记忆 + 状态更新

> 说明：本节是“方法创新草案”归档，不属于当前主线交付。

### 10.1 想法内容（草案）

目标是做一个统一框架：

1. 按 lead 自适应选择有效记忆长度（而非固定同一窗口）。  
2. 在起报时刻用可用观测做状态更新（DI/DA），减少初始状态偏差。  

简写可称为：`Lead-Adaptive Memory + State Update`。

### 10.2 当前证据能支持什么

当前实验只能支持：

1. 窗口长度收益是 lead-dependent（LT24 收益大，LT1/6 可能变差）。  
2. 历史流量输入对性能影响显著。  

当前实验不能直接支持：

1. “初始状态误差是唯一主因”。  
2. “DI/DA 一定有效”。  
3. “该方法已经优于现有方案”。

### 10.3 本想法的状态

- 状态：`parked`（已记录，暂不推进实现）  
- 原因：当前阶段优先维持主线归档状态，不新增实现负担。  

### 10.4 何时再启用

在以下条件满足后再启用本想法：

1. 明确恢复“补齐矩阵”目标并批准补跑 `Mamba LT12/LT24`。  
2. 固定窗口与 lead 分配窗口的验证流程固定。  
3. 明确 no-leak 规则下的状态更新接口（只允许 `t0` 及历史观测）。

---

## 11. 结果索引（高频文件）

- L7 总表：`results/04_namou_kuwei/L7_fair_all_models_LT1_6_12_24_summary.csv`  
- L8 状态：`results/04_namou_kuwei/L8_rainonly_current_status.csv`  
- L8 非 Mamba 总表：`results/04_namou_kuwei/L8_rainonly_nonmamba_LT1_6_12_24_summary.csv`  
- 窗口全 lead 对比：`results/04_namou_kuwei/L8_window_test_gru_all_leads_seq168_vs336.csv`  
- 窗口全 lead 图：`results/04_namou_kuwei/L8_window_test_gru_all_leads_nse_seq168_vs336.png`
