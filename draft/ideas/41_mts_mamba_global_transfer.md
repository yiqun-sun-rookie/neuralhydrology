# 41 - MTS-Mamba Global Transfer

**状态**: in_progress
**创建日期**: 2026-01-06
**最后更新**: 2026-02-23

> **整合说明（2026-02-23）**: 经 idea 重新评估，本 idea 成为 Mamba 研究主线的核心论文（WRR 级别）。已吸收以下 idea：
> - ID 02（mamba_camels_us）→ 归档，CAMELS-US 日尺度对比实验资产并入
> - ID 03（mamba_camelsh）→ 降格为本 idea 的小时级 LSTM baseline / Mamba fine-tuning target
> - ID 06（haihe_river）→ 降格为本 idea 的 data-scarce transfer case study
> - ID 99（global_hourly_model）→ 概念合并，不再独立推进
>
> 详见 `draft/IDEA_EVALUATION_2026_02.md`。

---

## 对话目的（最新）

围绕”MTS-Mamba 全球迁移学习”主线，完成三件事：

1. 将大规模训练从本地迁移到河海大学 HPC，解决算力与内存瓶颈；
2. 沉淀本对话遇到的 HPC 坑位及可复用解法；
3. 按项目规则将本任务代码、结果、日志和文档与其他任务隔离。

---

## Isolation Scope

| 类型 | 旧路径（历史） | 新路径（本任务唯一入口） | 说明 |
| :--- | :--- | :--- | :--- |
| Task Code | `common/`, `configs/caravan/`, `upload_to_hpc.ps1` | `src/mts_mamba_global_transfer/` | 本任务后续以 `src/mts_mamba_global_transfer/` 为准 |
| Task Results | `runs/`, `results/` | `results/41_mts_mamba_global_transfer/` | 本任务输出统一落盘 |
| Task Logs | `logs/` | `logs/41_mts_mamba_global_transfer/` | 本任务日志单独归档 |
| Task Docs | `TRAINING_PROGRESS.md`, `docs/technical/*` | 当前文档 + `src/mts_mamba_global_transfer/README.md` | 本任务上下文集中管理 |

---

## Code Index

| Component | Path | Description |
| :--- | :--- | :--- |
| Package Root | `src/mts_mamba_global_transfer/__init__.py` | 任务包入口 |
| Task Readme | `src/mts_mamba_global_transfer/README.md` | 本任务目录约定与执行入口 |
| HPC Setup | `src/mts_mamba_global_transfer/hpc/setup_hpc_env.sh` | 本任务 HPC 环境初始化脚本（UTF-8） |
| SLURM Submit | `src/mts_mamba_global_transfer/hpc/submit_caravan_global.slurm` | 本任务专用提交脚本 |
| Task Config | `src/mts_mamba_global_transfer/configs/caravan_daily_basemodel_hpc.yml` | 本任务训练配置 |
| Smoke Config | `src/mts_mamba_global_transfer/configs/caravan_daily_smoke_2basins_ep1.yml` | 本地最小训练验证（2 basins, 1 epoch） |
| Smoke Basins | `src/mts_mamba_global_transfer/data/smoke_2_basins.txt` | smoke 配置用 basin 列表 |
| Smoke Config (10x3) | `src/mts_mamba_global_transfer/configs/caravan_daily_smoke_10basins_ep3.yml` | 本地增强 smoke 验证（10 basins, 3 epochs） |
| Smoke Basins (10) | `src/mts_mamba_global_transfer/data/smoke_10_basins.txt` | 10-basin smoke 配置用 basin 列表 |
| **MTS-Mamba Model** | `neuralhydrology/modelzoo/mtsmamba.py` | **核心模型**：MTSMamba 类，Context Prepend 跨频率传递（218 行） |

---

## Results Index

| Run ID | Date | Output Path | Notes |
| :--- | :--- | :--- | :--- |
| 41_caravan_daily_smoke_10basins_ep3_2026_0218_1802_ep3 | 2026-02-18 | `results/41_mts_mamba_global_transfer/41_caravan_daily_smoke_10basins_ep3_2026_0218_1802_ep3/` | 本地 CPU smoke 完成（10 basins, 3 epochs）: NSE=0.57383, KGE=0.52536 |
| 41_caravan_daily_smoke_2basins_ep1_2026_0218_1256_ep1 | 2026-02-18 | `results/41_mts_mamba_global_transfer/41_caravan_daily_smoke_2basins_ep1_2026_0218_1256_ep1/` | 本地 CPU smoke 训练完成（2 basins, 1 epoch） |
| caravan_global_hpc_v1 | 2026-01-06 | `results/41_mts_mamba_global_transfer/` | 本任务独立结果目录（待写入） |
| 41_mtslstm_camels_hourly_4basins_ep3_2026_0224_2110_ep3 | 2026-02-24 | `results/41_mts_mamba_global_transfer/` | Phase 0 baseline: 4 basins 3ep CPU; hourly NSE=0.1486, KGE=0.1236 |
| 41_mtsmamba_camels_hourly_4basins_ep3_2026_0224_2128_ep3 | 2026-02-24 | `results/41_mts_mamba_global_transfer/` | Phase 0 experimental: 4 basins 3ep CPU; hourly NSE=0.1802, KGE=0.1144, ratio=1.21 PASSED |

---

## Progress Log

| Date | Event | Details |
| :--- | :--- | :--- |
| 2026-02-24 | Phase 0 对比实验完成 | MTS-Mamba vs MTS-LSTM (4 basins, 3ep, 1D+1h, CPU): hourly NSE ratio=1.21, 结论 PASSED（Mamba 略优） |
| 2026-02-24 | mtsmamba.py 实现并测试通过 | 实现方案 A (Context Prepend) 218 行，注册到 modelzoo factory。`test_multi_timescale_regression[mtsmamba]` PASSED，未破坏 mtslstm/odelstm。 |
| 2026-02-23 | 状态传递方案设计完成 | 调研 Mamba SSM 状态接口（mamba_ssm 不支持注入，HF transformers 通过 MambaCache 可注入）。设计 3 候选方案：A-Context Prepend / B-SSM State Injection / C-Cross-Attention Bridge。推荐先验证方案 A。 |
| 2026-02-23 | 技术风险评审 | 识别三大风险：状态传递不对等（高）、复杂度论据不成立（中）、竞争窗口收窄（中）。重排优先级：先验证状态传递方案，再铺规模实验。新增 Plan B 降级叙事。 |
| 2026-02-18 | 本地增强 smoke 验证通过 | 使用 `src/mts_mamba_global_transfer/configs/caravan_daily_smoke_10basins_ep3.yml` 在 CPU 上完成 10 basins/3 epochs，验证指标 NSE=0.57383, KGE=0.52536 |
| 2026-02-18 | 本地 smoke 验证通过 | 使用 `src/mts_mamba_global_transfer/configs/caravan_daily_smoke_2basins_ep1.yml` 在 CPU 上完成 2 basins/1 epoch，验证指标 NSE=0.44622, KGE=0.50352 |
| 2026-01-06 | 任务隔离初始化 | 建立 `draft/RESEARCH_INDEX.md` 与 `41` 任务专属目录 |
| 2026-01-06 | 对话产物归档 | 将 HPC 相关代码、配置、文档映射到 `src/mts_mamba_global_transfer/`、`results/41_mts_mamba_global_transfer/`、`logs/41_mts_mamba_global_transfer/` |
| 2026-01-06 | 规则对齐 | 对齐 `.cursor/00-project-structure.mdc` 与 `.cursor/10-hpc-workflow.mdc` 的隔离要求 |
| 2026-01-06 | HPC 经验沉淀 | 将本任务的 HPC 坑位与解决方案归档到仓库内文档体系 |

---

## 当前执行入口

```bash
# 提交本任务作业（在 HPC 上）
sed -i 's/\r$//' src/mts_mamba_global_transfer/hpc/*.slurm
sbatch src/mts_mamba_global_transfer/hpc/submit_caravan_global.slurm
```

### 本地最小 smoke（可复现）

```bash
python -m neuralhydrology.nh_run train --config-file src/mts_mamba_global_transfer/configs/caravan_daily_smoke_2basins_ep1.yml --gpu -1
python -m neuralhydrology.nh_run train --config-file src/mts_mamba_global_transfer/configs/caravan_daily_smoke_10basins_ep3.yml --gpu -1
```

---

## 对话成果（代码 / 结果 / 文档）

### 代码资产

- `src/mts_mamba_global_transfer/configs/caravan_daily_basemodel_hpc.yml`
- `src/mts_mamba_global_transfer/hpc/setup_hpc_env.sh`
- `src/mts_mamba_global_transfer/hpc/submit_caravan_global.slurm`
- `src/mts_mamba_global_transfer/hpc/upload_to_hpc.ps1`

### 结果与日志资产

- `results/41_mts_mamba_global_transfer/41_caravan_daily_smoke_2basins_ep1_2026_0219_1716_ep1/`
- 本地 smoke 验证指标（2026-02-19）：`NSE=0.44622`, `KGE=0.50352`
- `logs/41_mts_mamba_global_transfer/`（HPC 作业日志目录，仍可用于后续集群运行）

### 文档资产

- 本任务主文档：`draft/ideas/41_mts_mamba_global_transfer.md`
- 任务总入口：`draft/RESEARCH_INDEX.md`
- 计划文档：`.cursor/plans/mts-mamba全球迁移学习聚焦计划_41f8c99e.plan.md`

---

## 已识别并解决的 HPC 坑（摘要）

1. **本地 OOM**：32GB 无法承载 Caravan 全流域加载 -> 切换 HPC，申请 128GB+ 内存。
2. **SSH 登录限制**：密码 + OTP 使非交互登录困难 -> 使用外部原生 CMD 手动 SSH。
3. **终端兼容性**：集成终端与交互菜单不兼容（`TERM ERROR`/`Connection closed`）-> 外部 CMD 登录。
4. **大文件传输**：数据量大 -> 本地压缩后 `scp` 上传，HPC 端解压。
5. **调度规范**：禁止登录节点直跑 -> 统一通过 `sbatch` 提交 Slurm 脚本。

---

## 技术风险分析（2026-02-23 评审）

### 风险 1：状态传递机制不对等（高风险）

MTS-LSTM 的核心优势来自跨频率状态传递：日 LSTM 的 (h, c) 通过线性 FC 投影为小时 LSTM 的初始状态。这之所以有效，是因为：
- LSTM 的 (h, c) 语义清晰：h 是短期表征，c 是长期记忆
- LSTM 天然接受 (h₀, c₀) 作为初始状态

Mamba SSM **不具备这些特性**：
- 内部状态为 `[batch, d_inner, d_state]`，维度更高且语义不透明
- 官方 `mamba_ssm` 不支持初始状态注入（PR #488 未合并，且仅支持前向无梯度）
- HuggingFace `transformers` 后端通过 `MambaCache` 可注入初始 SSM state，但训练时梯度流待验证
- 若只传递 Mamba 最终输出向量（而非 SSM 内部状态），实质退化为特征拼接，丧失 MTS 的核心优势

#### 状态维度对比

| 模型 | 状态 | 维度 | 语义 |
|------|------|------|------|
| LSTM | h (hidden) | `[1, batch, hidden_size]` | 短期表征 |
| LSTM | c (cell) | `[1, batch, hidden_size]` | 长期记忆 |
| Mamba | ssm_state | `[batch, d_inner, d_state]` | SSM 运行状态（d_inner = hidden_size × expand） |
| Mamba | conv_state | `[batch, d_inner, d_conv]` | 因果卷积缓存 |

#### 候选方案详细设计（2026-02-23）

**方案 A：Context Prepend（上下文前缀注入）**

```
日 Mamba: x_daily[0:T_d] → mamba_daily → output[-1] → FC → context_token [batch, 1, hidden]
小时 Mamba: input = concat([context_token, x_hourly[0:T_h]]) → mamba_hourly → output[1:]
```

- 日 Mamba 输出最后一个时间步的隐藏表征，经 FC 投影后作为"上下文 token"前缀到小时序列
- Mamba 的选择性扫描会自然地将 context token 的信息吸收进 SSM 内部状态
- 最终输出丢弃 token 0（仅保留小时部分）
- **优点**：最简洁，不碰 Mamba 内部，任何后端通用，梯度流自然
- **缺点**：非显式状态传递，Mamba 能否从单个 token 充分吸收日尺度信息取决于模型容量
- **复杂度**：O(T_h + 1) ≈ O(T_h)，几乎无额外开销

**方案 B：SSM State Injection（SSM 状态直注入）**

```
日 Mamba: x_daily[0:T_d] → mamba_daily(use_cache=True) → 提取 cache.ssm_states
transfer_fc: [batch, d_inner_daily, d_state] → [batch, d_inner_hourly, d_state]
小时 Mamba: 将投影后的 ssm_states 写入 MambaCache → mamba_hourly(cache_params=cache)
```

- 通过 HuggingFace `MambaCache` 对象提取日 Mamba 的最终 SSM 状态
- 用可学习的线性层投影到小时 Mamba 的状态空间
- 将投影后的状态注入小时 Mamba 的 cache 作为初始状态
- **优点**：最忠实于 MTS-LSTM 的状态传递机制，信息量最大
- **缺点**：绑定 HuggingFace 后端；3D 状态投影参数量大（d_inner × d_state）；训练时梯度是否正确流过 cache 注入需实验验证
- **复杂度**：O(T_h) + 投影层参数
- **关键风险**：若 `MambaCache` 在训练模式下不传梯度，方案失效

**方案 C：Cross-Attention Bridge（跨频率注意力桥）**

```
日 Mamba: x_daily[0:T_d] → mamba_daily → daily_output [batch, T_d, hidden]
小时 Mamba (前半): x_hourly[0:T_h] → mamba_hourly → hourly_hidden [batch, T_h, hidden]
Bridge: MultiheadAttention(Q=hourly_hidden, K=daily_output, V=daily_output) → fused [batch, T_h, hidden]
小时 Mamba (后半/Head): fused → dropout → head → predictions
```

- 日 Mamba 输出全序列作为 KV，小时 Mamba 输出作为 Q
- 注意力层选择性地从日尺度信息中提取相关上下文
- **优点**：信息传递最灵活，可学习"何时关注日尺度哪个时间步"
- **缺点**：引入 O(T_h × T_d) 注意力开销；偏离 MTS-LSTM 的简洁设计；增加超参数（n_heads）
- **复杂度**：O(T_h × T_d)，当 T_h=3000, T_d=365 时约 1M 注意力计算

#### 方案推荐排序

| 优先级 | 方案 | 理由 |
|--------|------|------|
| 1 | **A: Context Prepend** | 最简洁、通用、无风险点，先验证"Mamba 是否能从 1 个 token 吸收足够上下文" |
| 2 | **B: SSM State Injection** | 最忠实于 MTS-LSTM，但需先验证 MambaCache 梯度流 |
| 3 | C: Cross-Attention Bridge | 最灵活但最重，仅在 A/B 都不够好时尝试 |

#### 最小验证实验计划

- **数据集**：CAMELS-US mini（10 basins），双频率（1D + 1H）
- **对比组**：MTS-LSTM baseline（已有实现）
- **实验组**：方案 A → 方案 B → 方案 C（顺序执行，若 A 达标则停止）
- **指标**：NSE, KGE（小时频率分支）
- **通过标准**：小时 NSE ≥ MTS-LSTM baseline 的 95%

### 风险 2：复杂度论据不成立（中风险）

- LSTM 本身就是 O(N)，Mamba 对标的是 O(N²) 的 Transformer
- Mamba 的实际速度优势来自并行扫描（常数因子优化），非渐近复杂度优势
- **论文叙事需调整**：不能以"比 LSTM 快"为卖点

### 风险 3：竞争窗口收窄（中风险）

已发表的 Mamba 水文论文：Demiray & Demir (2025)、RiverMamba (2025)、LightMamba (2024)。
到论文完成时"Mamba 用于水文"已不新鲜。**真正创新点必须是 multi-timescale + global transfer，而非 Mamba 本身**。

### Mamba 的真实优势场景

- 小时分支 seq_length=3000，Mamba 并行扫描可能比 LSTM 串行更快（训练效率）
- 选择性机制可能更好地捕获长程依赖（如数月前积雪对洪水的影响），但这是经验性假设

---

## 下一步计划（修订 2026-02-23）

> **原则**：先解决架构设计的技术不确定性，再铺规模实验。

### 阶段 0：状态传递方案设计与验证（最高优先级）

- [x] 精读 `neuralhydrology/modelzoo/mtslstm.py` 的状态传递实现，提取设计约束。
- [x] 精读 `neuralhydrology/modelzoo/mamba.py` 和 Mamba 后端源码，确认 SSM 状态接口。
- [x] 设计 3 个候选方案（Context Prepend / SSM State Injection / Cross-Attention Bridge）。
- [x] 实现方案 A (Context Prepend) `neuralhydrology/modelzoo/mtsmamba.py`（218 行，2026-02-24）。
- [x] 注册到 modelzoo factory，`test_multi_timescale_regression[mtsmamba]` 通过（2026-02-24）。
- [x] 配置 CAMELS-US mini 双频率对比实验（4 basins, 3 epochs, 1D+1H），MTS-Mamba vs MTS-LSTM。
- [ ] 若方案 A 不达标，继续验证方案 B（需先确认 MambaCache 梯度流）。
- **通过标准**：小时分支 NSE ≥ MTS-LSTM baseline 的 95%。

### 阶段 1：规模实验（原阶段 1+2 合并，骨架已在阶段 0 完成）

1. 修复 Mamba 在 Windows/HPC 的兼容性问题（如需要）。
2. 登录 HPC 检查 Caravan 作业状态，确认日尺度预训练权重。
3. CAMELS-US 全量对比：LSTM vs Mamba vs MTS-LSTM vs MTS-Mamba。
4. 日预训练 → 小时微调 transfer 验证。

### 阶段 2：规模实验

1. 登录 HPC 检查 Caravan 作业状态，确认日尺度预训练权重。
2. CAMELS-US 全量对比：LSTM vs Mamba vs MTS-LSTM vs MTS-Mamba。
3. 日预训练 → 小时微调 transfer 验证。

### 阶段 2：跨区域迁移与论文

1. US → GB/AUS 迁移验证。
2. 海河 case study（如数据就绪）。
3. 整理论文图表与指标。

---

## 最终目标（论文）

**Plan A（首选叙事）**：MTS-Mamba + Caravan 全球日预训练在小时级洪水预报上优于 MTS-LSTM，尤其在洪峰时间刻画和跨区域泛化（US → GB/AUS）上更优。

**Plan B（降级叙事）**：若 MTS-Mamba 状态传递效果不显著优于 MTS-LSTM，论文退守为"全球多尺度预训练迁移框架"的系统性研究，Mamba 降格为消融实验中的一个 backbone 选择，重点放在 global pretraining + multi-timescale transfer 的方法论贡献上。

---

## 新对话一键接手提示

复制下面内容即可开启下一次会话：

```text
继续任务 mts_mamba_global_transfer（阶段 0 剩余：MTS-Mamba vs MTS-LSTM 对比实验）。

已完成：
- 技术评审：识别 3 大风险，设计 3 候选方案（详见 "技术风险分析" 章节）
- mtsmamba.py 已实现（218 行，Context Prepend 方案），注册到 modelzoo，单元测试通过
- 关键文件：neuralhydrology/modelzoo/mtsmamba.py, neuralhydrology/modelzoo/__init__.py

本次要做：
1) 写两个双频率 config（放 src/mts_mamba_global_transfer/configs/）：
   - MTS-Mamba: model=mtsmamba, dataset=hourly_camels_us, use_frequencies=[1D, 1h], 10 basins, 3 epochs
   - MTS-LSTM baseline: model=mtslstm, 其余相同
   参考现有测试 config: test/test_configs/multi_timescale_regression.test.yml
   本地 CAMELS-US 小时数据已就绪。
2) 在本地 CPU 跑两组实验，对比小时分支 NSE/KGE
3) 将结果记录到本文档 Results Index

通过标准：小时分支 NSE ≥ MTS-LSTM baseline 的 95%。
要求：仅使用 src/mts_mamba_global_transfer、results/41_mts_mamba_global_transfer、logs/41_mts_mamba_global_transfer 作为任务路径。
背景：详见 draft/ideas/41_mts_mamba_global_transfer.md
```
