# Idea 12: FSOI-Driven Adaptive Data Assimilation

> **创建日期**: 2026-03-30
> **状态**: Brainstorming 完成，待启动
> **依赖**: forecast_system_lite 中的 DA 诊断论文 (P1)
> **代码基座**: `G:\github\pycharm\projects\forecast_system_lite`

## 核心动机

P1 (DA 诊断论文) 发现：
- **S (production store) 修正在湿润流域短 LT 有害** (74% harmful at LT=2)
- **R (routing store) 修正在 LT=3 最优** (94% beneficial)
- 存在气候依赖反转 (干旱流域 S 反而有益)
- Blanket Q-mask 能改善 LT=1，但丢失了 26-45% 的有益 S 修正
- **FSOI 与 Q 存在循环依赖**: Q→K→Δx→FSOI，换 Q 可能改变 FSOI 结论

**问题**: 能否把 FSOI 从事后诊断工具升级为实时 DA 优化的驱动信号？

## 完整 Idea 清单 (20 个)

### 第一类: FSOI 可靠性 (基础研究)

| ID | Idea | 描述 | 难度 | 论文归属 |
|----|------|------|------|---------|
| D1 | FSOI 符号对 Q 的鲁棒性 | Q 变 100×，"S 有害"结论是否成立？扰动 α∈{0.1..10}×Q_NMC | 低 | P2 |
| D2 | FSOI 符号对 R 的鲁棒性 | 同 D1 但扰动 R | 低 | P2 |
| D3 | FSOI 符号对模型的鲁棒性 | 换 HBV/XAJ/Sacramento，跨模型结论是否迁移 | 中 | 远期 |
| D4 | FSOI 符号对 DA 方法的鲁棒性 | UKF vs EnKF vs EKF，同 basin 符号一致性 | 中 | 远期 |

### 第二类: FSOI 驱动的 Q/R 调优 (核心方法)

| ID | Idea | 描述 | 难度 | 论文归属 |
|----|------|------|------|---------|
| Q1 | FSOI 迭代调 Q | 每轮用 FSOI 符号压 harmful 状态 Q_ii，γ=0.5 迭代收敛 | 低 | P2 |
| Q2 | FSOI 比例步长调 Q | 按 FSOI 幅度连续缩放 Q_ii (非二值 mask) | 低 | P2 |
| Q3 | Lead-time-specific Q 优化 | 对不同 LT 分别优化 Q*，得到一组专用滤波器 | 中 | P2/P3 |
| Q4 | 气候条件化 Q | Q = f(aridity, area, ...)，用 FSOI 跨 basin 学映射 | 中 | P2 扩展 |
| Q5 | 端到端梯度优化 Q | ∂J/∂Q 直接优化 (已在 kalmannet_qr 完成) | — | ✅ 已完成 |

**注意**: Q5 与 FSOI 无直接关系，是纯优化方法，可作为 Oracle 上界对比。

### 第三类: 在线自适应修正 (实时质控)

| ID | Idea | 描述 | 难度 | 论文归属 |
|----|------|------|------|---------|
| O1 | FSOI 符号预测器 | 训练 MLP，用 innovation/状态/强迫 预测 FSOI 正负 | 中 | P4 |
| O2 | 滞后 FSOI 代理 | 用最近 k 步已实现 FSOI 作为当前步代理信号 | 低 | P2 可选 |
| O3 | 实时代理指标 | 找与 FSOI 相关的可实时算的量 (innovation 幅度、‖Δx‖、VR) | 中 | P4 |
| O4 | 逐步 accept/reject 门控 | UKF update 后根据 O1/O2/O3 决定是否回滚修正 | 中 | P4 |
| O5 | 软门控 (加权修正) | x_post = x_prior + w·K·y，w∈[0,1] 由预测器输出 | 中 | P4 |

### 第四类: IMM 多模型融合

| ID | Idea | 描述 | 难度 | 论文归属 |
|----|------|------|------|---------|
| M1 | 多 Q-策略 IMM | Expert_i = UKF(Q*_LTi)，IMM 按 innovation 分配权重 | 中 | P3 |
| M2 | 多状态选择 IMM | Expert_1 只修正 R，Expert_2 修正 S+R，Expert_3 全修正 | 中 | P3 |
| M3 | FSOI-informed 转移概率 | 用 FSOI 信号调 IMM 转移矩阵 (接 Agentic-KF 思路) | 高 | P3 |
| M4 | 气候自适应 IMM | 湿润用 Expert-R，干旱用 Expert-S，IMM 自动切换 | 中 | P3 |

### 第五类: 扩展应用

| ID | Idea | 描述 | 难度 | 论文归属 |
|----|------|------|------|---------|
| E1 | 多观测源 FSOI | 同化土壤水分/雪/地下水时，FSOI 揭示哪个观测源有害 | 高 | 远期 |
| E2 | 分布式模型 FSOI | 对空间分布式模型逐网格 FSOI → 空间选择性修正 | 高 | 远期 |
| E3 | FSOI 用于 LSTM DA | 接 Latent-UKF 项目，对 LSTM 隐状态做 FSOI | 高 | 远期 |
| E4 | FSOI 用于模型结构诊断 | 根据 FSOI 判断模型缺陷 (S 有害→产流方程有问题?) | 高 | 远期 |

## 论文规划

```
P1 (已有): DA 诊断框架 — FSOI 引入水文 DA
 ├─ 状态: 论文草稿完成，审稿修改中
 └─ D1, D2 可作为 revision 补充实验

P2 (下一篇): 诊断驱动的自适应 Q 调优
 ├─ 核心: D1 + D2 (鲁棒性) → Q1 + Q2 + Q3 (迭代调 Q)
 ├─ 对比: FSOI-iter vs blanket mask vs Q5(Oracle)
 ├─ 可选: O2 (滞后 FSOI) 或 Q4 (气候条件化)
 └─ 叙事: "诊断可信 → 诊断驱动优化 → 性能提升"

P3 (IMM): 多预报时效自适应 DA
 ├─ 核心: Q3 的产出作为 IMM Expert → M1 + M2 + M4
 ├─ 复用: paper-imm-variable-params 已有 IMM 框架
 └─ 叙事: "不同 LT 需要不同修正策略 → IMM 自动选择"

P4 (在线质控): 实时 FSOI 预测与门控
 ├─ 核心: O1 + O4 或 O5
 └─ 叙事: "不需要未来观测也能判断修正好坏"

远期:
 └─ D3, D4, E1-E4
```

## FSOI-Q 循环依赖问题

核心矛盾: Q → P_pred → K → Δx → FSOI，改 Q 会改变 FSOI。

三种处理路线:
1. **迭代收敛** (路线 1): Q⁰→FSOI⁰→Q¹→...→收敛。用于 P2。
2. **鲁棒性证明** (路线 2): 证明 FSOI 符号对 Q 不敏感。P2 的第一组实验。
3. **端到端优化** (路线 3): ∂J/∂Q 直接优化，绕开 FSOI。已完成 (Q5)，作为对比上界。

**建议**: P2 = 路线 2 (证明可靠) + 路线 1 (迭代调优)。

## 与已有项目的关系

| 项目 | 关系 |
|------|------|
| forecast_system_lite | 主代码基座 (诊断框架 + GR4J + CAMELS) |
| paper-imm-variable-params | IMM 框架复用 (P3) |
| kalmannet_qr | Q5 端到端优化结果作为 Oracle |
| kalmannet/latent_da | E3 Latent-UKF FSOI 的扩展方向 |
| filters | DA 工具库 (UKF, EnKF 实现) |
| neuralhydrology/xaj_global_pilot | D3 跨模型验证 (XAJ/HBV) |
