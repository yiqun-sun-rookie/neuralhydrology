# Idea 10: 全球概念水文模型对比 — XAJ vs HBV vs GR4J

> **状态**: proposal（待讨论）
> **创建日期**: 2026-03-27
> **优先级**: 待定
> **目标期刊**: HESS / Journal of Hydrology / WRR

---

## 1. 动机与背景

### 1.1 研究空白

全球尺度的概念水文模型对比研究中，主流模型（HBV、GR4J、VIC、mHM）均来自欧美学派。**新安江模型（XAJ）作为中国水文学最具代表性的概念模型，从未在全球尺度上被系统评估过。**

现有文献：
- Beck et al. (2016, 2020): 全球大规模水文模型对比，未包含 XAJ
- Perrin et al. (2001): 法国流域 19 个模型对比
- Knoben et al. (2020): 模型结构 vs 参数的重要性，未涉及 XAJ
- Kratzert et al. (2019): LSTM vs 概念模型（CAMELS-US），XAJ 缺席

### 1.2 为什么值得做

1. **三大水文学派首次全球对决**：
   - **中国学派**: 新安江模型（XAJ）— 蓄满产流 + B 曲线
   - **北欧学派**: HBV — 幂律产流 + 线性水库
   - **法国学派**: GR4J — 产流-汇流双库极简结构

2. **结构差异有理论意义**：
   - XAJ: 蓄满产流（saturation excess）— 适合湿润气候
   - HBV: 超渗产流（infiltration excess）— 通用设计
   - GR4J: 4 参数极简主义 — 参数效率最高

3. **实际需求**: 全球水文预报系统（如 GloFAS）选模型时需要跨气候区对比证据

---

## 2. 初步实验结果

### 2.1 先导实验（2026-03-27 完成）

在 15 个 CAMELS-US 流域（5 snow + 5 humid + 5 semi-arid，分层随机抽样）上完成了 HBV 和 XAJ 变体的公平对比。

**实验设置**:
- 率定: CMA-ES, 5000 evals × 3 restarts, 365 天 warmup
- 训练期: 1990-10-01 ~ 1995-09-30
- 测试期: 2000-10-01 ~ 2005-09-30

**中位 Test NSE 结果**:

| 模型 | 参数数 | 求解器 | 雪区(5) | 湿润(5) | 半干旱(5) | 总体(15) |
|------|--------|--------|---------|---------|-----------|----------|
| H1 SuperflexPy-HBV | 12 | 隐式 Euler | 0.654 | **0.689** | 0.149 | **0.646** |
| X2 XAJ+PDD | 20 | 显式 Euler | **0.715** | 0.672 | **0.212** | 0.637 |
| H4 子步HBV (dt=1/4) | 12 | 显式 Euler | 0.580 | 0.420 | 0.043 | 0.493 |
| X1 经典XAJ (无融雪) | 14 | 显式 Euler | 0.106 | 0.597 | 0.194 | 0.307 |
| H2 NumPy-HBV (简化) | 10 | 显式 Euler | 0.479 | 0.186 | 0.009 | 0.268 |

**关键发现**:
1. XAJ+PDD 和 SuperflexPy-HBV **总体接近**（0.637 vs 0.646）
2. 雪区 XAJ+PDD 优于 HBV（0.715 vs 0.654）— PDD 度日法更好
3. 湿润区 HBV 略好（0.689 vs 0.672）
4. 半干旱区所有模型都差（最好 0.212）
5. PDD 对雪区贡献巨大: +0.61 NSE（X1→X2）
6. **HBV 性能对数值求解器极度敏感**（隐式 vs 显式 Euler 差 0.35 NSE），XAJ 不敏感（子步仅 +0.01）

### 2.2 先导实验的局限

- 只有 15 个流域，统计显著性不足
- 缺少 GR4J 作为第三方基准
- CAMELS-US 只覆盖北美
- 参数数量不公平（XAJ 20 vs HBV 12 vs GR4J 4）

---

## 3. 论文设计

### 3.1 标题（草案）

**"Three Schools of Rainfall-Runoff Modeling: A Global Benchmark of XAJ, HBV, and GR4J"**

或更保守:
**"Is the Xinanjiang Model Globally Applicable? A Cross-Climate Comparison with HBV and GR4J on 531 Basins"**

### 3.2 核心研究问题

1. **XAJ 在全球不同气候区的表现如何？** 与国际主流模型（HBV、GR4J）相比，差距还是打平？
2. **模型结构 vs 参数数量 vs 数值方案**：哪个因素对性能影响最大？
3. **不同产流机制（蓄满 vs 超渗 vs 双库）在哪些气候区有优势？**

### 3.3 实验矩阵

| 模型 | 产流机制 | ET 方案 | 融雪 | 参数 | 来源 |
|------|---------|---------|------|------|------|
| XAJ | B 曲线蓄满产流 | 三层级联 | 无 | 14 | 中国 (赵人俊, 1984) |
| XAJ+PDD | B 曲线 | 三层级联 | PDD 度日 | 20 | 本文 |
| HBV | 幂律 | 平滑 (m) | 指数平滑 | 12 | 瑞典 (Bergström, 1976) |
| GR4J | 产流库 | 截留 + 产流库 | 无 | 4 | 法国 (Perrin, 2003) |
| GR4J+PDD | 产流库 | 截留 + 产流库 | PDD 度日 | 10 | 本文 |

### 3.4 流域与数据

**方案 A（稳妥）**: CAMELS-US 531 basins
- 优点: 数据质量高、社区标准、与 Kratzert 等可比
- 缺点: 只有北美

**方案 B（有野心）**: Caravan 多数据集
- CAMELS-US (531) + CAMELS-GB (671) + CAMELS-AUS (222) + LamaH-CE (882)
- 优点: 真正的全球覆盖、跨大陆验证
- 缺点: 数据格式不统一、PET 计算方法不同、工作量大

**建议**: 先做方案 A，投稿时如果 reviewer 要求更广覆盖再补 B。

### 3.5 评估指标

- NSE, KGE, PBIAS（标准三件套）
- 高流量偏差（peak bias, top 20%）
- 低流量偏差（low-flow bias, bottom 20%）
- FDC 偏差（flow duration curve）
- **参数效率**: NSE / 参数数（GR4J 天然优势）

### 3.6 论文结构

| Section | 内容 |
|---------|------|
| Introduction | 三大学派背景、XAJ 全球空白、研究问题 |
| Models | XAJ/HBV/GR4J 方程对比（统一数学符号） |
| Data & Methods | CAMELS-US 531, CMA-ES 率定, 评估指标 |
| Results | Table 1: 总体表现; Fig 1: 气候区箱线图; Fig 2: CDF 曲线; Fig 3: 空间地图 |
| Discussion | 结构差异归因、参数效率、数值方案敏感性、对实际应用的启示 |
| Conclusions | XAJ 全球潜力、模型选择建议 |

### 3.7 预期 Figures & Tables

| 编号 | 类型 | 内容 |
|------|------|------|
| Table 1 | 结果 | 5 模型 × 4 气候区 中位 NSE/KGE |
| Table 2 | 结果 | 参数效率排名 (NSE per parameter) |
| Fig 1 | 箱线图 | 按气候区的 NSE 分布（类似 Knoben 2020 风格） |
| Fig 2 | CDF | 531 basins 的 NSE 累积分布曲线 |
| Fig 3 | 地图 | 每个 basin 的最佳模型空间分布 |
| Fig 4 | 散点 | XAJ NSE vs HBV NSE, 按气候区着色 |
| Fig 5 | 消融 | XAJ 组件贡献（B 曲线 vs 三层 ET vs PDD） |
| Fig S1 | 补充 | 数值方案敏感性（HBV 显式 vs 隐式 vs 子步） |

---

## 4. 可行性评估

### 4.1 已有基础

| 组件 | 状态 | 位置 |
|------|------|------|
| XAJ Numba 实现 | ✅ 完成 | `src/xaj_global_pilot/xaj_numba.py` |
| XAJ+PDD 耦合 | ✅ 完成 | 同上 |
| HBV SuperflexPy | ✅ 完成 | `external/superflexpy/` + `hydroagent/environment.py` |
| GR4J SuperflexPy | ✅ 有组件 | `external/superflexpy/.../gr4j.py` |
| CMA-ES 率定框架 | ✅ 完成 | `xaj_global_pilot/xaj_model.py` |
| CAMELS-US 数据加载 | ✅ 完成 | `hydroagent/data_loading.py` |
| 531 basin HBV 结果 | ✅ 完成 | `results/08_hbv_camels_us_531/` |
| 15 basin 对比结果 | ✅ 完成 | `results/benchmark_conceptual_models_15basins.csv` |
| GR4J+PDD 耦合 | ❌ 需实现 | — |
| 531 basin XAJ 率定 | ❌ 需 HPC | — |
| 531 basin GR4J 率定 | ❌ 需 HPC | — |

### 4.2 工作量估算

| 任务 | 预估时间 |
|------|---------|
| GR4J+PDD 实现 + 测试 | 2-3 天 |
| 531 basin × 5 模型 HPC 率定 | 1-2 周（HPC 计算时间） |
| 结果分析 + 作图 | 1 周 |
| 论文写作（初稿） | 2-3 周 |
| **总计** | **5-7 周** |

### 4.3 HPC 计算需求

| 模型 | 每 basin 时间 | 531 basins 总时间 | 并行策略 |
|------|-------------|-----------------|---------|
| XAJ (14p) | ~50s | ~7h | 11 chunks × 1h |
| XAJ+PDD (20p) | ~450s | ~66h | 11 chunks × 6h |
| HBV (12p) | ~200s | ~29h | 已有结果 |
| GR4J (4p) | ~30s | ~4h | 11 chunks × 0.5h |
| GR4J+PDD (10p) | ~100s | ~15h | 11 chunks × 1.5h |

总 HPC 需求：~120 GPU-hours（实际是 CPU，不需要 GPU）

### 4.4 风险评估

| 风险 | 概率 | 影响 | 应对 |
|------|------|------|------|
| XAJ 和 HBV 完全一样好 | 高 | 中 | 叙事转为"三学派殊途同归" |
| GR4J 4 参数碾压所有人 | 中 | 高 | 讨论参数效率 vs 绝对性能 |
| 半干旱区所有模型崩溃 | 高 | 低 | 已知限制，诚实报告 |
| Reviewer 要求加 LSTM 对比 | 高 | 中 | 加一行 Kratzert (2019) 文献结果 |
| Reviewer 说参数数量不公平 | 高 | 中 | Table 2 参数效率分析 + GR4J 天然对照 |

---

## 5. 与现有 Idea 的关系

- **Idea 09 (XAJ Global Pilot)**: 本 idea 是 09 的自然延伸和升级，从 pilot 8 basins → 531 basins
- **Idea 07 (HydroAgent)**: HydroAgent 的 SuperflexEnv 提供 HBV/GR4J 运行环境
- **SCL-LSTM**: 如果后续做可微 XAJ，可复用 SCL-LSTM 的 PyTorch 框架

---

## 6. 讨论要点（与同事讨论用）

### 6.1 核心卖点
- **首次** XAJ 全球评估 — 填补文献空白
- **三大学派**对决 — 叙事有吸引力
- **数值方案发现** — HBV 对求解器敏感而 XAJ 不敏感，这是新知识
- **GR4J 4 参数对比** — 参数效率角度是 reviewer 容易 appreciate 的

### 6.2 需要讨论的决策
1. **投稿目标**: HESS（开放获取, IF~6）vs JoH（传统, IF~6）vs WRR（高影响, IF~5.4, 但竞争更激烈）
2. **数据范围**: 先 CAMELS-US 531 还是直接上 Caravan？
3. **是否加可微版本**: 纯率定对比 vs 加可微参数学习（工作量翻倍但创新性更高）
4. **合作者**: 是否需要 XAJ 方向的资深合作者增加可信度？
5. **时间线**: 和 Idea 41 (Mamba) 的优先级如何平衡？

### 6.3 最坏情况
- 结果：三个模型全球表现无显著差异
- 对策：改叙事为 "Model structure matters less than calibration strategy"，仍可发 JoH
- 参考：Knoben et al. (2020) 得出类似"结构不是关键"的结论，发了 WRR

### 6.4 最好情况
- 结果：XAJ 在湿润季风气候显著优于 HBV/GR4J
- 对策：强调蓄满产流机制对亚热带/热带气候的天然适配性
- 影响：改变全球水文建模中忽视中国模型的现状

---

## 7. 下一步行动

- [ ] 与同事讨论本提案
- [ ] 决定投稿目标和数据范围
- [ ] 实现 GR4J+PDD 耦合
- [ ] 在 15 basins 上加入 GR4J 验证
- [ ] 提交 HPC 531-basin 全模型率定任务
