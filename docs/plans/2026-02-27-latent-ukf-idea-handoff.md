# Latent-UKF for LSTM Hydrology: Idea Handoff (For New Chat)

## 1) 你现在的核心想法（一句话）
在水文时序预测中，对 LSTM/GRU 的隐藏状态做数据同化（DA），并将同化放在低维 latent 空间里用 UKF 更新（Latent-UKF），以提升长 lead time 和稀疏观测条件下的预测稳定性与精度。

## 2) 现有证据（你已经拿到的关键信号）

### 2.1 窗口长度实验显示“状态记忆”非常关键
文件: `results/04_namou_kuwei/L8_window_test_seq168_vs336_gru_LT24.csv`

- 设定: `GRU + LT24 + rain-only`
- `seq_length: 168 -> 336`
- NSE: `-0.1166 -> 0.1203` (delta `+0.2369`)
- RMSE: `74.99 -> 66.56`

解释: 模型明显受益于更长历史，支持“初始状态/系统慢变量恢复不充分”这个判断。DA 的目标正是在线修正状态估计，因此方向合理。

### 2.2 多模型公平对比表明长 lead 仍有挑战
文件: `results/04_namou_kuwei/L7_fair_all_models_LT1_6_12_24_summary.csv`

- 短 lead（如 LT1）整体指标高。
- lead 增大后（6/12/24）性能下滑明显，说明误差传播和状态漂移问题显著。

这为“状态同化而非仅输出后处理”提供了问题驱动。

## 3) 方法定义（避免概念混淆）

你要做的 Latent-UKF 不是“简单压缩输出”，而是针对 **recurrent hidden state** 的同化框架:

1. 预测步（model forecast）
- 冻结或半冻结 DL-SSM（LSTM/GRU）滚动得到先验状态 `h_{t|t-1}` 和先验流量 `y_{t|t-1}`。

2. 状态压缩（encoder）
- `z_{t|t-1} = E(h_{t|t-1}, context_t)`，其中 `z` 维度远小于 `h`。

3. UKF 同化（latent space）
- 在 `z` 上执行 UKF 更新，观测是 `q_obs`（可扩展多观测）。
- 得到后验 `z_{t|t}`, `P_{t|t}`。

4. 状态回写（decoder）
- `h_{t|t} = D(z_{t|t}, context_t)`（或直接修正预测量，但首选修正 hidden state）。
- 用后验状态继续下一时刻递推。

5. 可选自适应协方差
- `Q/R` 可学习（trainable）或在线自适应（Berry-Mehra 类思路）。

其中 `context_t` 可以包含动态输入窗口摘要和静态属性嵌入（见第 6 节）。

## 4) 是否有创新（客观边界）

### 4.1 不是空白
- “LSTM + DA/UKF”已有相关工作。
- “latent 空间 DA”在洪水/径流方向也已有 3D/4D-Var 类工作。

### 4.2 你的可创新点
若做到以下组合，创新是有机会成立的:

1. 面向水文 DL recurrent hidden state 的 **latent-space UKF**（不是输出端后处理）。
2. **Q/R 自适应** 与 **稀疏观测鲁棒性**（100/50/25% + 连续缺测）。
3. 完整公平矩阵（multi-lead + multi-seed + strong baselines + 显著性检验）。

### 4.3 会被认为增量的情况
1. 仅“LSTM 上套 UKF”，但不解释 latent 设计与机制收益。
2. 只在单站点/单 lead 有效。
3. 缺乏与 `open-loop`, `qshift`, `EnKF/VarDA` 等强基线对比。

## 5) 与 End-to-End 的关系

- **Option A（当前推荐）**: Post-hoc Latent-UKF adapter  
  冻结主模型，只训练/调优 adapter+UKF 参数。优点是机制清晰、论文可解释性强。

- **Option B**: End-to-End joint training  
  DL-SSM + encoder/decoder + UKF 参数一起训练。上限可能更高，但训练不稳、归因困难。

建议: 先 A 建立证据，再用小规模 B 做增益验证。

## 6) “静态属性条件化”是什么意思

不是必须项，但有价值。含义是:
- 用静态流域属性 `s` 经过 MLP 得到 `e_s`；
- 在 encoder/decoder 或转移函数里把 `e_s` 作为条件输入（concat/FiLM/gating）；
- 作用是让不同流域的状态几何更可分、latent 同化更稳。

在你的语境下可以理解为“给 latent 表示加 basin-specific 先验约束”。

## 7) 当前代码与工程进度（已落地）

### 7.1 资源门控约束已接入（你特别要求的）
文件: `src/namou_kuwei/scripts/run_experiment.py`

- 在 `train/evaluate/quick` 前增加运行时容量检查。
- 条件包括:
  - CPU 使用率阈值
  - 可用内存阈值
  - GPU 可用显存与利用率（`nvidia-smi`）
- 若资源不足或无法安全检查，直接 `skip`（fail-closed）。

### 7.2 对应测试已通过
文件: `test/test_namou_kuwei_scripts.py`

- 新增“资源不足时不启动训练”的测试。
- 本地已跑: `pytest test/test_namou_kuwei_scripts.py -q`，结果 `4 passed`。

### 7.3 已有实施计划文档
文件: `docs/plans/2026-02-26-latent-ukf-neuralhydrology.md`

- 包含 6 个任务: protocol -> hidden export -> latent adapter -> UKF bridge -> missingness stress -> summary pipeline。

## 8) 你下一步最优执行序列（建议直接照做）

1. 固化 L9 协议（固定 baselines / leads / seeds / 指标 / 缺测设定）。
2. 先做 hidden rollout 导出（时间对齐 `qobs`, `y_hat`, `h_t`）。
3. 实现最小可用 latent adapter（先线性，再 MLP）。
4. 桥接你已有 Trainable-UKF（来自 `kalmannet/filters`）。
5. 先跑 LT24 单站小规模验证，再扩展到 LT1/6/12/24 全矩阵。
6. 报告里先给机制证据（状态误差收敛、创新项残差、缺测退化曲线），再给总体指标。

## 9) 论文叙事模板（可直接用）

问题:
“长 lead 与稀疏观测下，水文 DL 模型状态漂移显著，开环误差累积导致预报劣化。”

方法:
“提出针对 recurrent hidden state 的 Latent-UKF 同化框架，在低维空间执行不确定性传播和观测更新，并引入自适应 Q/R 增强鲁棒性。”

贡献:
1. 首次/系统化将 latent-space UKF 同化用于水文 DL hidden state（以实验定义为准）。
2. 在多 lead 与观测缺失场景下显著优于 open-loop 与 qshift 基线。
3. 提供可复现协议与失败边界分析。

## 10) 新对话可直接粘贴的启动 Prompt

```text
我在 neuralhydrology 项目中做水文预报。我要推进一个 Latent-UKF 方案:
- 目标: 对 LSTM/GRU hidden state 做同化，不是仅输出后处理。
- 现有证据: seq_length 168->336 在 GRU+LT24 上 NSE -0.1166->0.1203, RMSE 74.99->66.56。
- 约束: 运行训练/评估前必须检查本地 CPU/GPU/内存，资源不足就不能运行。
- 当前状态: run_experiment.py 已加资源门控并有测试通过。
- 我希望你按工程顺序实现: L9 protocol -> hidden export -> latent adapter -> ukf bridge -> missingness stress -> summary pipeline。
请先给出第1步最小可提交改动，并直接改代码+测试。
```

## 11) 参考文献（当前讨论用）
- LSTM-UKF (J Hydrol 2024): https://doi.org/10.1016/j.jhydrol.2024.131819
- UKF+RNN (Water 2020): https://doi.org/10.3390/w12020578
- LSTM learning EnKF update (The Cryosphere 2025): https://tc.copernicus.org/articles/19/4759/2025/tc-19-4759-2025.html
- Variational DA for differentiable hydrology comparison (arXiv 2025): https://arxiv.org/abs/2502.16444
- Latent 3D-Var flood forecasting (ICCS Workshops 2025): https://doi.org/10.1007/978-3-031-97567-7_4
- Latent 4D-Var river discharge (IEEE JSTARS 2025): https://doi.org/10.1109/JSTARS.2025.3611136

---

如果后续要进一步提高“创新确定性”，重点补三件事:
1. 明确 latent-UKF 与已有 LSTM-UKF/latent-Var 的机制差异；
2. 给出稀疏观测与极端事件下的稳定性曲线；
3. 做跨流域泛化或至少跨时期鲁棒性验证。
