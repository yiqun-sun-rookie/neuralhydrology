# Idea 10: TANGO — Time-Alternating Neural-Geophysical Operator

**状态**: `paused` — 架构验证完成，empirical 优势不足，暂停
**代码路径**: `src/scl_hydro/`
**文献新颖性**: 确认（24 篇对比，无先例）

---

## 一、演化历程

本 idea 经历了 5 个阶段的演化，最终形成 TANGO 架构。

### 阶段 1: SCL-LSTM (State Continuity Loss)

**想法**: 用 L2 loss 惩罚两个重叠时间段在相同时间点的 LSTM 隐状态差异，迫使模型学到一致的流域状态。

**组件**:
- ObsEncoder: 小 LSTM 编码 [P,T,Q_obs] → LSTM 初始状态 (h_0, c_0)
- Overlapping Segment Pairs: 两段时间有重叠的训练数据
- StateContinuityLoss: `λ * mean(||h_k(t) - h_{k+1}(t)||²)`

**Phase 1 实现**: 完成（17 tests pass）。`config.py`, `model.py`, `loss.py`, `dataset.py`, `trainer.py`

**结论**: ❌ **SCL loss 不提升 NSE**
- 3-way pilot (8 basins): Vanilla LSTM 0.714, Encoder-only 0.710, SCL-LSTM 0.692
- SCL 反而拖后腿（Encoder 有效但不新颖，SCL loss 无正面效果）
- **根本原因**: SCL 约束隐状态一致性 ≠ 更好的预测。LSTM 训练已直接优化预测 loss，加 SCL 是多余约束。

### 阶段 2: LSTM 参数化 HBV (NH HybridModel 思路)

**想法**: LSTM 逐时间步输出 HBV 的 10 个参数，HBV 用这些参数跑物理方程。

**结论**: ❌ **LSTM 没学会生成好参数**
- 3-basin pilot: Coupled 0.466 vs Pure LSTM 0.714 vs Pure HBV 0.674
- 诊断发现 LSTM 输出的参数几乎不随时间变化（std < 3% of range）
- 等于一个"很差的固定参数 HBV 率定"
- **根本原因**: 105 个训练 segment 对参数化任务完全不够。MLP（不需 LSTM）在全序列上到 NSE=0.94，证明动态参数化本身可行，但 LSTM 分段训练信息不足。

### 阶段 3: LSTM 修正 HBV 状态 / 输出残差

**想法**: HBV 用固定参数跑，LSTM 修正物理状态或输出 Q 残差。

**结论**: ⚠️ **接近但不如 pure baseline**
- 状态修正版: 3-basin mean 0.692 (vs LSTM 0.714, HBV 0.674)
- 改善了 HBV (+0.019) 但不如 LSTM (-0.021)
- **根本原因**: 架构不是用户想要的"交替执行"

### 阶段 4: 真正交替执行 + Encoder/Decoder 桥 (TANGO)

**想法**: HBV 和 LSTM 严格交替执行，每个时间步只有一个模型运行。GatedEncoder 在 HBV 步后更新 LSTM 的 h/c，Decoder 在 LSTM 步后输出物理状态。

**架构**:
```
t=0 (HBV):  HBV(state, forcing, fixed_params) → state', Q
            GatedEncoder([state', forcing, Q], h, c) → h', c'
t=1 (LSTM): LSTM(forcing, (h', c')) → lstm_out
            Decoder(lstm_out) → state'', Q
...交替
```

**组件**:
- `DifferentiableHBV`: PyTorch HBV，与 NumPy 版数值一致（8 tests, max err 2.3e-6）
- `GatedStateEncoder`: GRU-like 门控更新 h/c（不覆盖，保留记忆）
- `StateDecoder`: 2-layer MLP, softplus × std + mean
- `CoupledHydroModel`: 交替循环 + configurable stride（15 tests）

**文献检索**: 24 篇相关工作对比，确认三个独有特征组合无先例:
1. 真正交替执行（不是加和/参数化/修正）
2. Encoder/decoder 桥接不同维度状态空间
3. 两者作为独立状态转移系统

### 阶段 5: 多变量约束学习 (方向探索)

**想法**: TANGO 输出物理状态，用 SWE/SM 遥感数据约束。

**结论**: ❌ **跑题了**
- 多变量约束不是 TANGO 独有——纯 LSTM + 多输出头同样可做
- Kratzert/Frame/Feng 已有大量相关工作
- 用 SAC-SMA 模型输出当"真值"不合理

---

## 二、实验结果汇总

### 过拟合诊断 (单流域 01013500, 2 segments, 500 epochs)

| 模型 | train NSE | 结论 |
|------|-----------|------|
| Pure LSTM | 0.999 | 完美过拟合 |
| TANGO (各种 encoder 变体) | 0.933 | 有容量瓶颈 |
| HBV 步理论天花板 | 0.893 | TANGO > 天花板 → 状态传递有效 |

**LSTM 步 NSE=0.9999, HBV 步 NSE=0.867** → 瓶颈 100% 在 HBV 步

### Stride sweep (单流域 01013500, test NSE)

| Stride | HBV% | test NSE |
|--------|------|----------|
| Pure HBV | 100% | 0.723 |
| 2 | 50% | 0.695 |
| 3 | 33% | 0.744 |
| 5 | 20% | 0.767 |
| **10** | **10%** | **0.820** |
| 30 | 3.3% | 0.783 |
| Pure LSTM | 0% | 0.734 |

**存在最优 stride=10 超过两个 pure baseline。** 单流域证据最强。

### Per-basin 验证 (8 CAMELS basins, stride=10)

| Basin | HBV | LSTM | TANGO | T>H? | T>L? |
|-------|-----|------|-------|------|------|
| 01013500 | 0.723 | 0.774 | **0.789** | ✓ | ✓ |
| 01022500 | 0.541 | **0.668** | 0.619 | ✓ | ✗ |
| 02051500 | 0.573 | **0.677** | 0.508 | ✗ | ✗ |
| 03450000 | 0.210 | **0.623** | 0.474 | ✓ | ✗ |
| 07056000 | 0.198 | 0.672 | **0.761** | ✓ | ✓ |
| 07291000 | 0.140 | **0.477** | 0.178 | ✓ | ✗ |
| 09035900 | 0.756 | 0.684 | **0.749** | ✗ | ✓ |
| 12010000 | 0.609 | **0.869** | 0.800 | ✓ | ✗ |
| **Mean** | 0.469 | **0.681** | 0.610 | 6/8 | 3/8 |
| **Median** | 0.557 | 0.675 | **0.684** | — | — |

**TANGO 6/8 胜 HBV (+0.141)，但只 3/8 胜 LSTM (-0.071 mean)**

### Multi-basin pooled (8 basins, avg HBV params)

| | HBV | LSTM | T-2 | T-5 | T-10 |
|---|---|---|---|---|---|
| Mean | 0.469 | **0.647** | -0.303 | 0.289 | 0.479 |

**Multi-basin 训练时 TANGO 远不如 LSTM** — avg params + 统一 encoder 统计不适用。

### 多变量约束 (01013500)

| 模型 | Q NSE | SWE NSE |
|------|-------|---------|
| TANGO (Q only) | **0.789** | -0.196 |
| TANGO (Q+SWE) | 0.758 | **0.635** |

SWE 约束改善雪状态估计但不是 TANGO 独有能力。

---

## 三、关键发现与教训

1. **SCL loss 无正面效果**: 约束隐状态一致性 ≠ 更好的预测
2. **LSTM 参数化 HBV 需要大量数据**: 小数据下 LSTM 学不会生成好参数
3. **交替架构在单流域 work**: stride=10 超过 pure LSTM 和 pure HBV
4. **Multi-basin 是关键难题**: 需要 per-basin HBV params + basin identifier
5. **HBV 质量决定 TANGO 上下限**: HBV 好的流域 TANGO 赢 LSTM，HBV 差的流域 TANGO 输
6. **多变量约束不是独有优势**: 任何 DL + 多输出头都能做

---

## 四、未验证的方向（后续可捡起）

| 方向 | 核心假设 | 验证方式 | 优先级 |
|------|---------|---------|--------|
| A. PUB (无资料流域) | 物理约束改善泛化 | Leave-N-basins-out，需 multi-basin 先解决 | 中 |
| B. 物理模型诊断 | LSTM 步 vs HBV 步状态差异揭示 HBV 缺陷 | 可视化分析 | 低 |
| C. 气候变化外推 | HBV 做物理安全网 | Split-sample (dry→wet) | 低 |
| D. 数据稀缺 | 少量数据时物理结构正则化 | 训练数据量消融 | 中 |

---

## 五、代码清单

| 文件 | 内容 | Tests |
|------|------|-------|
| `src/scl_hydro/config.py` | SCLConfig (Phase 1 遗留) | 3 |
| `src/scl_hydro/model.py` | ObsEncoder + SCLCudaLSTM (Phase 1) | 4 |
| `src/scl_hydro/loss.py` | StateContinuityLoss (Phase 1) | 4 |
| `src/scl_hydro/dataset.py` | SCLDataset + SingleSegDataset | 3 |
| `src/scl_hydro/trainer.py` | SCLTrainer (Phase 1) | 2 |
| `src/scl_hydro/hbv_torch.py` | **DifferentiableHBV** | 8 |
| `src/scl_hydro/coupled_model.py` | **CoupledHydroModel + GatedEncoder + Decoder** | 15 |
| `src/scl_hydro/data_utils.py` | CAMELS 加载 + 归一化 | — |
| `src/scl_hydro/evaluation.py` | 评估工具 | — |
| `src/scl_hydro/scripts/pilot_experiment.py` | SCL pilot | — |
| `src/scl_hydro/scripts/pilot_coupled.py` | Coupled pilot | — |
| `src/scl_hydro/scripts/tango_perbasin.py` | **Per-basin 验证** | — |
| `src/scl_hydro/scripts/tango_8basin_sweep.py` | Multi-basin stride sweep | — |
| `src/scl_hydro/scripts/tango_multivar.py` | 多变量约束实验 | — |
| `test/test_scl_hydro_e2e.py` | E2E smoke test | 1 |
| `test/test_scl_hydro_hbv_torch.py` | HBV NumPy/PyTorch 一致性 | 8 |
| `test/test_scl_hydro_coupled_model.py` | TANGO 架构测试 | 15 |
| **总计** | | **63 tests** |

---

## 六、可复用资产

即使 TANGO 本身暂停，以下组件对其他项目有价值：

1. **DifferentiableHBV** (`hbv_torch.py`): 完整可微 HBV，梯度率定比 CMA-ES 快 10-20 倍。可用于任何需要可微概念模型的项目。
2. **CAMELS 数据工具** (`data_utils.py`): 加载 + PET 计算 + z-score 归一化，可复用。
3. **GatedStateEncoder**: 门控状态桥接，可用于任何物理-ML 耦合场景。
4. **Overfit 诊断方法**: 先验证过拟合能力 → 再扩大数据，是通用的 ML 诊断流程。

---

## 七、Git 历史

| Commit | 内容 |
|--------|------|
| `a9cdf89` | SCLConfig (Phase 1 Task 1) |
| `2120bb0` | ObsEncoder |
| `4421285` | SCLCudaLSTM |
| `38bb623` | E2E smoke test |
| `4fab8a5` | Training script + config |
| `6aba24b` | **DifferentiableHBV + CoupledHydroModel** |
| `1d354b7` | TANGO idea doc |
| `da41543` | Per-basin validation + MLP decoder |
| `8f7be48` | 4 application directions |
| `0c9d599` | Multi-variable constraint experiment |
