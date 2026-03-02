# KuWei 会话终结交接文档（可直接用于新对话接力）

更新时间：2026-03-02  
适用范围：`src/namou_kuwei` 主线（no-leak 复现 + 公平对比）

## 1. 本轮对话实际完成了什么

本轮围绕 KuWei 主线做了以下工作：

1. 明确主线目标，剥离旁线想法，回归 `kuwei` 核心复现任务。  
2. 完成多模型公平对比（L7：含历史流量滞后输入）。  
3. 完成 rain-only 公平对比主体实验（L8：无历史流量输入，Mamba LT12/LT24 归档留空）。  
4. 做了 GRU 的窗口长度对照（`seq_length=168 vs 336`，LT1/6/12/24）。  
5. 产出跨版本总对比（L7 vs L8）CSV、Markdown、图表与示意图。  
6. 执行并复查 no-leak 约束（配置与输入层面）。  
7. 生成可直接用于讨论/写作的结果文件与图。

## 2. 当前主线目标（最终共识）

KuWei 主线目标是：

1. 在严格 no-leak 约束下复现小时级预报。  
2. 在同等预算下公平比较多个 DL 模型。  
3. 分离“输入信息增益”和“架构增益”（尤其历史流量输入的作用）。  
4. 形成可继续扩展的、可审计的实验资产（配置、结果、图、文档）。

已明确：`lead-adaptive memory + DI/DA` 为旁线想法，已归档，非当前交付主线。

## 3. no-leak 与公平性协议（执行基准）

### 3.1 统一时间划分（L7/L8一致）

- Train: `2020-01-01` 到 `2021-06-30`  
- Validation: `2021-07-01` 到 `2021-12-31`  
- Test: `2022-01-01` 到 `2022-12-31`

### 3.2 L7 与 L8 的唯一区别（核心对照变量）

- L7：`Rain + qobs_shift{lead} + 24 static`  
- L8：`Rain_shift{lead} + 24 static`（不使用 `qobs_shift*`，不使用 `autoregressive_inputs`）

### 3.3 公平预算（L7/L8一致）

- `epochs=60`  
- `batch_size=256`  
- `seq_length=168`（窗口实验除外）  
- `seed=2025`  
- `loss=NSE`

### 3.4 泄露判据

- 绝不允许未来实测流量进入预测输入。  
- L7 的 `qobs_shift{lead}` 属于历史滞后流量（允许）。  
- L8 不含流量输入（更严格）。  
- `qobs` 不允许直接放入 `dynamic_inputs`。

## 4. 关键结果（截至 2026-03-02）

## 4.1 L7（含历史流量滞后输入）

来源：`results/04_namou_kuwei/L7_fair_all_models_LT1_6_12_24_summary.csv`

- 每个 leadtime 的最佳 NSE 均为 `GRU`：
  - LT1: `0.995604`
  - LT6: `0.940459`
  - LT12: `0.827649`
  - LT24: `0.725159`

## 4.2 L8（rain-only，无历史流量）

来源：`results/04_namou_kuwei/L8_rainonly_current_status.csv`

- 每个已完成 leadtime 的最佳 NSE 仍为 `GRU`，但整体为负：
  - LT1: `-0.170600`
  - LT6: `-0.166612`
  - LT12: `-0.188640`
  - LT24: `-0.116616`

- 归档空项（按当前决策不补跑）：
  - `Mamba, LT12`
  - `Mamba, LT24`

## 4.3 L7 vs L8 综合对照（新增 L9）

来源：
- `results/04_namou_kuwei/L9_fair_histflow_vs_rainonly_comparison.csv`
- `results/04_namou_kuwei/L9_fair_histflow_vs_rainonly_comparison.md`

主要结论：

- 对所有已完成的 `model × leadtime`，加入历史流量后 NSE 均显著提升。  
- 典型提升量（`with_histflow_NSE - rainonly_NSE`）约 `+0.72` 到 `+1.17`。  
- 说明该任务中历史流量信息是决定性输入，不是边际特征。

## 4.4 窗口长度实验（GRU, L8）

来源：`results/04_namou_kuwei/L8_window_test_gru_all_leads_seq168_vs336.csv`

`seq336 - seq168` 的 NSE 变化：

- LT1: `-0.0930`
- LT6: `-0.0885`
- LT12: `+0.0336`
- LT24: `+0.2369`

结论：窗口收益是 lead-dependent，不是“越长越好”。

## 5. 图与可视化索引

1. L7 NSE 曲线：`results/04_namou_kuwei/L7_fair_nse_vs_leadtime.png`  
2. L8（非 Mamba）NSE 曲线：`results/04_namou_kuwei/L8_rainonly_nonmamba_nse_vs_leadtime.png`  
3. L8 GRU 全 lead 窗口对比：`results/04_namou_kuwei/L8_window_test_gru_all_leads_nse_seq168_vs336.png`  
4. L7 vs L8（按模型与lead并排）：`results/04_namou_kuwei/L9_fair_histflow_vs_rainonly_NSE_by_lead_model.png`  
5. 会话示意图（输入方案+公平条件+结论）：`results/04_namou_kuwei/L9_kuwei_schematic_histflow_vs_rainonly.png`

## 6. 代码与配置资产（本主线）

### 6.1 关键配置目录

- L7 公平对比：`src/namou_kuwei/configs/no_leak/07_model_fair/`
- L8 公平对比：`src/namou_kuwei/configs/no_leak/08_model_fair_rain_only/`
- no-leak 总入口说明：`src/namou_kuwei/configs/no_leak/README.md`

### 6.2 关键脚本

- 训练/评估入口：`src/namou_kuwei/scripts/run_experiment.py`
  - 包含运行资源门控（CPU/内存/GPU检查），避免爆内存。  
- 泄露检查：`src/namou_kuwei/scripts/validate_config.py`
  - 校验时间切分重叠、AR配置、`qobs`误用等。  
- 站点检查：`src/namou_kuwei/scripts/check_site.py`

### 6.3 相关测试文件

- `test/test_namou_kuwei_scripts.py`
- `test/test_namou_kuwei_validate_config.py`

## 7. 旁线想法状态（已归档）

已在 `draft/ideas/04_namou_kuwei.md` 的“旁线想法归档”中记录：

- 主题：`Lead-Adaptive Memory + State Update (DI/DA)`  
- 当前状态：`parked`  
- 原因：先完成 KuWei 主线闭环与公平矩阵。

## 8. 归档项与是否需要重启

当前保留空项：

1. L8 `Mamba LT12`  
2. L8 `Mamba LT24`

处理决策（2026-03-02）：

- 主线结论场景：不再补跑，直接归档。  
- 仅当目标转为“论文附表完整 5模型×4lead 无空项”时，再重启补跑。

补跑尝试记录：

- 已启动过 `L8 Mamba LT12`，后按用户要求中止。  
- 日志：  
  - `results/04_namou_kuwei/L8_mamba_LT12_train_20260301_223835.out.log`  
  - `results/04_namou_kuwei/L8_mamba_LT12_train_20260301_223835.err.log`
- 备注：日志提示 Mamba 走 fallback 顺序实现（非快路径），训练性价比偏低。

## 9. 操作经验与踩坑记录

1. 资源管理必须前置：先检查 GPU 空闲显存与系统内存，再启动长训练。  
2. Mamba 在当前环境可能缺少快路径依赖，速度显著下降。  
3. rain-only 条件下，静态特征无法替代历史流量信号。  
4. 长窗口提升集中在长 lead（LT24），短 lead 可能被噪声/过平滑拖累。  
5. 报告时必须把“已证实事实”和“机制猜想”分开，避免过度解释。

## 10. 给新对话的建议执行顺序

1. 默认按“主线已归档”处理，不新增长训练。  
2. 若需补齐附表，再单独重启 L8 Mamba LT12/LT24，并刷新 L8/L9 汇总。  
3. 若推进新方法，先固定 no-leak 协议与公平预算，再做 DI/DA 或 lead-adaptive memory。  
4. 所有新增结论必须先落地到 `results/04_namou_kuwei/` 和 `draft/ideas/04_namou_kuwei.md`。

## 11. 新对话可直接复制的接力提示词

可直接使用：

```text
请接管 KuWei 主线，先读取 docs/plans/2026-03-02-kuwei-conversation-handoff.md。
目标：在 no-leak 与公平预算不变前提下维护归档状态。
先报告当前归档项与是否需要重启训练，再开始。
```

若要补齐矩阵：

```text
按 handoff 文档补齐 L8 的 Mamba LT12/LT24，完成后更新 L8_rainonly_current_status.csv、
L9_fair_histflow_vs_rainonly_comparison.csv 和对应图表。
```

## 12. 当前工作区注意事项（非常重要）

当前仓库是 dirty worktree，存在大量与 KuWei 无关的变更。新对话中应：

1. 只操作 `src/namou_kuwei`、`results/04_namou_kuwei`、`draft/ideas/04_namou_kuwei.md` 等主线路径。  
2. 不要误回滚其他模块改动。  
3. 提交前先人工核对本次改动范围。

---

附：KuWei 主文档（持续更新）  
`draft/ideas/04_namou_kuwei.md`
