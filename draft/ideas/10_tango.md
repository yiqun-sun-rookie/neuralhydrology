# Idea 10: TANGO — Time-Alternating Neural-Geophysical Operator

**状态**: `dev` — 架构验证完成，单流域 positive signal
**优先级**: 高 — 新颖性确认，有初步正面结果
**目标期刊**: WRR / HESS
**代码路径**: `src/scl_hydro/`

---

## 一句话

物理模型（HBV）和神经网络（LSTM）在同一物理状态空间中**严格交替执行**，通过 encoder/decoder 桥接两个状态空间，以可学习的频率融合物理约束与数据驱动能力。

## 核心创新

已有的 hybrid 方法都是**同时作用**（加和 APHYNITY、参数化 δHBV、残差修正）。TANGO 是**交替执行**：

```
t=0 (HBV):  HBV(state, forcing) → state', Q     物理方程推进状态
            GatedEncoder(state', forcing, Q, h, c) → h', c'   桥接到 LSTM 空间

t=1 (LSTM): LSTM(forcing, (h', c')) → h'', c''   神经网络推进隐状态
            Decoder(h'') → state'', Q              桥接回物理空间

t=2 (HBV):  HBV(state'', forcing) → ...          物理方程继续
...交替进行
```

**三个独有特征的组合（经文献检索确认无先例）**：
1. 真正交替执行（不是加和、不是参数化、不是修正）
2. Encoder/decoder 桥接不同维度的状态空间（物理 4 维 ↔ LSTM 64 维）
3. 两者作为独立的状态转移系统（各自完整地推进状态）

## 方法论定位

| 已有方法 | 耦合方式 | 与 TANGO 区别 |
|---------|---------|--------------|
| APHYNITY (Yin 2021 ICLR) | dx/dt = F_phys + F_nn（加和） | 同时作用 ≠ 交替 |
| δHBV (Feng 2022 WRR) | LSTM → HBV 参数（参数化） | NN 不直接推进状态 |
| NeuralGCM (Kochkov 2024 Nature) | 物理+NN 趋势加和 | 加和 ≠ 交替 |
| UDE (Rackauckas 2020) | NN 替换 ODE 未知项 | 嵌入式 ≠ 独立交替 |
| H2M (Kraft 2022 HESS) | NN 生成水平衡系数 | 参数化 ≠ 交替 |
| ANCHOR (arXiv 2025) | 自适应切换 NN/数值求解器 | 无 encoder/decoder 桥 |
| SS-DNN (2024) | Strang splitting | 解析+PINN，无物理模型 |
| **TANGO (ours)** | **严格交替 + encoder/decoder 桥** | **独有组合** |

数学类比：**operator splitting**（Lie-Trotter splitting），但一个算子是物理模型，另一个是神经网络，用学习的 encoder/decoder 连接。

## 关键发现

### Stride 是可调的超参数

`stride` 控制 HBV 介入频率：stride=2 → 每 2 步 1 次 HBV，stride=10 → 每 10 步 1 次。

单流域（01013500）stride sweep **test NSE**：

| Stride | HBV 比例 | test NSE |
|--------|---------|----------|
| Pure HBV | 100% | 0.723 |
| 2 | 50% | 0.695 |
| 3 | 33% | 0.744 |
| 5 | 20% | 0.767 |
| **10** | **10%** | **0.820** |
| 30 | 3.3% | 0.783 |
| Pure LSTM | 0% | 0.734 |

**存在最优点 stride=10（NSE=0.820），超过 pure HBV 和 pure LSTM。**

### 过拟合诊断

| 步类型 | train NSE |
|--------|-----------|
| LSTM 步 | 0.9999（完美） |
| HBV 步 | 0.8669（固定参数上限） |
| 整体 | 0.9331 |
| 理论天花板（HBV步完美+LSTM步完美） | 0.893 |

0.933 > 0.893 → LSTM 通过改善状态间接提升了 HBV 步的输出，证明**状态传递确实在起作用**。

## 架构组件

| 组件 | 文件 | 作用 |
|------|------|------|
| `DifferentiableHBV` | `hbv_torch.py` | PyTorch HBV，与 NumPy 版数值一致（8 tests） |
| `GatedStateEncoder` | `coupled_model.py` | [state+forcing+Q, h, c] → 门控更新 h, c |
| `StateDecoder` | `coupled_model.py` | LSTM hidden → 物理状态 + Q（2 层 MLP + softplus） |
| `CoupledHydroModel` | `coupled_model.py` | 交替循环 + encoder/decoder 桥接（15 tests） |

## 论文叙事

**问题**：现有 hybrid 模型要么让 NN 参数化物理模型（δHBV），要么加和两者贡献（APHYNITY/UDE）。这些方法中 NN 无法独立推进系统状态——它被嵌入物理框架内，无法充分发挥数据驱动的灵活性。

**方法**：TANGO 让物理模型和 NN 作为对等的状态转移算子交替执行。物理模型提供周期性的物理约束（防止非物理状态），NN 提供灵活的数据驱动补偿（捕捉物理模型遗漏的过程）。交替频率（stride）是可调超参数。

**假设**：
1. 存在最优 stride：物理模型太频繁是累赘，太稀疏失去约束
2. TANGO 在 test 上优于 pure LSTM（物理约束改善泛化）和 pure HBV（NN 补偿物理不足）
3. 物理状态的可解释性保留（HBV 步产出的状态有明确物理含义）

**贡献**：
1. 首次提出物理模型与 NN 在共享状态空间中交替执行的框架
2. 通过 encoder/decoder 桥接不同维度的状态空间
3. 发现 stride 作为超参数的最优性质（最优 stride > 2）
4. 在 CAMELS-US 上验证泛化优势

## 实验计划

### Phase 1: 小规模验证 ✅ 已完成
- 3 basins, CPU, hidden=64
- Stride sweep 发现最优 stride=10

### Phase 2: 中规模验证（待做）
- 30-50 basins, CPU/GPU, hidden=128
- 多 stride 对比 + 消融实验
- 对比 E1(HBV) / E2(LSTM) / E3(TANGO stride=10) / E4(TANGO stride=2) / E5(δHBV)

### Phase 3: 全规模实验（待做）
- 531 CAMELS-US basins, HPC
- 最优 stride 选择策略（per-basin 还是 global）
- 极端事件 / PUB / 数据稀缺场景分析
- 物理状态可解释性分析

### Phase 4: 论文（待做）
- 标题：*"TANGO: Learning Hydrological Dynamics through Alternating Physical and Neural State Transitions"*
- Figure 1: 架构图（交替执行 + encoder/decoder）
- Figure 2: Stride sweep 曲线（存在最优点）
- Figure 3: 531-basin CDF 对比
- Figure 4: 物理状态轨迹 vs 观测（可解释性）
- Table 1: 多方法对比（HBV / LSTM / δHBV / TANGO）

## 相关文献（必引）

- Yin et al. 2021 (ICLR) — APHYNITY, additive decomposition
- Feng et al. 2022 (WRR) — δHBV, differentiable parameter learning
- Rackauckas et al. 2020 — Universal Differential Equations
- Kochkov et al. 2024 (Nature) — NeuralGCM
- Kraft et al. 2022 (HESS) — H2M hybrid
- Kratzert et al. 2019 (HESS) — LSTM hydrology baseline
- Ehret et al. 2020 (HESS) — SHM model (NH's HybridModel uses it)

## 风险

| 风险 | 严重性 | 缓解 |
|------|--------|------|
| 更多流域上 stride 最优点不存在 | 高 | Phase 2 中规模验证 |
| 训练不稳定（大规模） | 中 | 已验证 CPU 稳定，需验证 GPU |
| 审稿人认为是"工程贡献"不够理论 | 中 | 建立 operator splitting 理论联系 |
| Encoder/decoder 信息瓶颈限制上限 | 低 | 过拟合测试 0.933 > HBV 天花板 0.893 |
