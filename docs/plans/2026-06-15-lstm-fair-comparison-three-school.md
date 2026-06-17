# LSTM(Kratzert/Nearing 架构)与三学派概念模型公平对比 — 完整训练与对比方案

> 目标:在与三学派概念模型(GR4J/XAJ/HBV, CAMELS-US 531, repro_v01)**完全相同的公平协议**下,
> 用 **Kratzert 2019 (HESS) 架构**训练 LSTM,给出端到端训练 + 对比方案。LSTM 作为 531-DA 论文的
> **DL 天花板参考线**(概念模型是过程模型天花板)。
>
> 状态:DRAFT v1(待 5 轮独立审核后定稿)。**0 张图前,先锁协议。**

---

## 0. 一句话设计

同 531 basins / 同 reverse split(train 1999–2008, eval 1989–1999)/ 同 Maurer forcing / 同 NSE 指标,
LSTM 用 Kratzert 2019 原架构(EA-LSTM 与 LSTM+static, hidden 256, seq 270, 27 静态属性, 8-seed 集成,
NSE\* 损失, 固定 30 epoch 无早停),与既有冻结的 GR4J/XAJ/HBV 逐 basin NSE 做配对统计对比;
另在 **447 共同子集**上做文献定位(并自带"复现 Kratzert 0.74"的正确性闸门)。

---

## 审核结论(5 轮独立自验证 agent,各带 Bash/Read/Web 实证)

5 个独立 agent 全部判定 **pass_with_fixes**。下列修订**已并入本文档**:

**两条高一致性问题(5/5 confirmed)**:
1. **R1 原判反了**(已纠为非阻断):NSE per-basin 尺度不变 + 两管线各自 sim/obs 同尺度 → 概念模型与 LSTM 的
   原生 NSE **本就可直接比,无需统一 obs**;原"统一 obs"方案反而会单方面压低 LSTM。详见 §6 R1。
2. **validation 配置 bug**(已纠):`validate_n_random_basins:0 + validate_every` 不是关闭,而是"全 531 每 N epoch
   验证一次"的巨量无用算力。已改为**不设 validate_every = 关闭**(忠实 Kratzert 无验证/无早停)。

**其余已并入的修订**:lr schedule 改 `{0,11,21}`(nh 循环 1-indexed,原 R6 推断错);§7 严禁 447/集成 与
531/single 混排,头条改 LSTM-single vs 概念-single + Holm 多重校正;447 锁定为 5-published 交集并物化成文件、
按架构分别设闸门(cudalstm 0.758±0.03 / ealstm 0.742±0.03)+ Maurer 版本 caveat;8-seed 把 seed 拼进
experiment_name 防 run 目录冲突;EA-LSTM Python 循环更慢、串行 16 runs 实为 1.5–2.5 天;Maurer Tmax==Tmin 注记。

**审核独立确认为正确(refuted 的疑点 = 已验证无误)**:全部 Kratzert 超参忠实(hidden 256/seq 270/dropout 0.4/
batch 256/30 epoch/forget-bias 5/clip 1/8 seed)、`loss:NSE`=NSE\*(eps=0.1)、27 属性齐全零 NaN(比 nh 示例更忠实)、
maurer 列名精确匹配、`data/camels_us` 路径无需 `/full`、日期覆盖与无泄漏、两个 531 列表逐一相同、概念模型用
**修正版 PT PET**(非低偏 bug)、负流量两管线都置 NaN。

---

## 1. 基准协议:三学派 repro_v01 的精确设置(对齐锚点)

| 维度 | 值 | 来源 |
|---|---|---|
| Basins | 531(`src/xaj_global_pilot/configs/conceptual_benchmark_camels_us_531_repro.txt`,与 `examples/06-Finetuning/531_basin_list.txt` **逐一相同**) | 已核验 set diff = 0 |
| Calibration | 1999-10-01 → 2008-09-30 (9 WY) | `src/xaj_global_pilot/config.py:77-78` |
| Evaluation | 1989-10-01 → 1999-09-30 (10 WY), reverse split | `config.py:79-80` |
| Warmup(概念模型) | 评估前 1 日历年(1988-10-01→1989-09-30), 从默认初态前演, 末态作 eval 初态 | runner `--warmup-year` |
| Forcing | **maurer**, 变量 prcp/tmax/tmin/srad/vp/dayl | `data/camels_us/basin_mean_forcing/maurer/` |
| PET(概念模型) | Priestley-Taylor, α=1.26 | `src/hydroagent/data_loading.py:51-111` |
| Obs Q | `usgs_streamflow/*_streamflow_qc.txt`, cfs→mm/d, **用 `area_gages2`(camels_topo.txt)归一** | `data_loading.py:225-247` |
| 指标 | NSE(eval 期), 逐 basin → median/mean | `metrics.py` |
| 预算 | CMA-ES 5000×3, seed 42+restart·1000 | `hbv_lite_cma_calibrate.py:136` |
| 冻结结果(median NSE, full-531) | GR4J **0.6533** / XAJ **0.6196** / HBV **0.6170** | `three_school_fairness_completion_20260608.md` |

> 权威协议/数字/caveat 以 `docs/technical/three_school_fairness_completion_20260608.md` 为准。
> 复用进 DA 线见 `docs/technical/three_school_as_da_baseline_reuse.md`。

---

## 2. Kratzert 2019 原文设置(LSTM 复刻目标)

Kratzert et al. 2019, HESS 23, 5089–5110, doi:10.5194/hess-23-5089-2019;代码 github.com/kratzert/ealstm_regional_modeling。

| 项 | 值 |
|---|---|
| 架构 | (a) 标准 LSTM + static(属性逐时刻拼接); (b) **EA-LSTM**(属性仅进 input gate)。两者各跑。 |
| hidden/cell | **256**, 单层 + FC(dropout 0.4) |
| 序列长度 | **270** 天(seq-to-value) |
| Forcing | **Maurer**, 5 变量:prcp, tmin, tmax, srad, vp |
| 静态属性 | **27** 个 CAMELS 属性(气候9/地形3/植被5/土壤8/地质2) |
| 周期 | train 1999-10-01→2008-09-30; test 1989-10-01→1999-09-30(reverse split,与 repro_v01 **完全一致**) |
| 集成 | **8** 个随机 seed, 预测**逐时刻取均值** |
| 损失 | **basin-averaged NSE\***(Eq.13), 权重含 per-basin std + **ε=0.1** |
| 优化 | Adam, lr 1e-3 →(epoch 11)5e-4 →(epoch 21)1e-4; batch 256; **30 epoch**; dropout 0.4; grad-clip 1.0; forget-bias 5 |
| 归一化 | 动态+静态+target 全部零均值单位方差 |
| 早停 | **无**。固定 30 epoch。超参由 **basins-only k-fold(k=4)CV** 选定,**从不接触 1989-1999 评估期** → 评估期是干净 held-out。 |
| 基准对比子集 | **447**(所有模型都有有限 NSE 的交集) |

**Kratzert 文献基准(447 子集, median NSE)**:EA-LSTM ens **0.742** / LSTM+static ens **0.758** /
SAC-SMA+Snow17 **0.603** / mHM-basin **0.666** / HBV-upper **0.676** / VIC-basin 0.551 / FUSE902 0.650。

**"Nearing"定位**:Nearing et al. 2021 WRR(e2020WR028091)是**评论/框架文**,直接重绘 Kratzert 2019 的
531-basin 结果,不提供新超参,不可作架构来源。NSE\* 损失源自 Kratzert 2019(非 Nearing)。531-basin
子集与 SAC-SMA/VIC 基准的真正出处是 **Newman et al. 2017 (J. Hydrometeorol.)**。多 forcing 变体见
Kratzert et al. 2021 HESS(Daymet+Maurer+NLDAS, seq 365, 10-seed)——**本方案不用多 forcing**(为与
概念模型同 forcing 公平,锁单一 Maurer)。

---

## 3. 本仓基础设施核验(已落实)

- `model: cudalstm`(= 标准 LSTM+static)与 `model: ealstm`(= EA-LSTM)均支持。
- `loss: NSE` = `MaskedNSELoss(eps=0.1)`,`weights=1/(per_basin_std+0.1)²`(`neuralhydrology/training/loss.py:239-255`)
  → **就是 Kratzert NSE\***。✓
- `QObs(mm/d)` 归一:`28316846.592*QObs*86400/(area*1e6)`,area 取**forcing 文件头**(`camelsus.py:249, 182`)。
  ⚠️ 与概念模型用的 `area_gages2` **可能不同源**(见 §6 风险 R1)。
- 数据齐备:`data/camels_us/{basin_mean_forcing/maurer, usgs_streamflow, camels_attributes_v2.0}`。
- 集成:`neuralhydrology/utils/nh_results_ensemble.py::create_results_ensemble`(逐时刻均值后重算指标)。
- 已有 LSTM 配置**不可直接复用**:`results/05_*`(NSE 0.754)用的是 **Daymet + hidden 128 + 1990/2000 时间顺序 split**,
  与本协议(Maurer/256/reverse split)不符;但 `src/adversarial/configs/train_531_*.yml` 已是 reverse split,可作骨架参考。

---

## 4. LSTM 训练配置(生产 YAML)

主配置 `cudalstm`(LSTM+static,最强,作 DL 上界);`ealstm` 仅改 `model: ealstm` 并去掉与 EA-LSTM 不兼容项。
建议放 `src/lstm_fair_531/configs/`(新建 idea 工作区)。

```yaml
# src/lstm_fair_531/configs/kratzert2019_cudalstm_maurer_531.yml
experiment_name: kratzert2019_cudalstm_maurer_531
run_dir: results/18_lstm_fair_531           # 新 idea id (待 RESEARCH_INDEX 登记)
dataset: camels_us
data_dir: data/camels_us

train_basin_file: src/xaj_global_pilot/configs/conceptual_benchmark_camels_us_531_repro.txt
validation_basin_file: src/xaj_global_pilot/configs/conceptual_benchmark_camels_us_531_repro.txt
test_basin_file: src/xaj_global_pilot/configs/conceptual_benchmark_camels_us_531_repro.txt

# --- periods: 与 repro_v01 / Kratzert 完全一致 ---
train_start_date: '01/10/1999'
train_end_date:   '30/09/2008'
validation_start_date: '01/10/1980'   # 现已不用(validation 关闭); 保留仅为 schema 完整, 1980-1989 与 train/test 不重叠
validation_end_date:   '30/09/1989'
test_start_date:  '01/10/1989'
test_end_date:    '30/09/1999'

# --- model: Kratzert 2019 ---
model: cudalstm            # ealstm 变体另起一份
hidden_size: 256
initial_forget_bias: 5
output_dropout: 0.4
output_activation: linear

# --- training ---
optimizer: Adam
loss: NSE                  # = MaskedNSELoss(eps=0.1) = Kratzert NSE*(审核 5/5 确认)
learning_rate:             # nh 训练循环 1-indexed; key 0 仅初始化优化器(审核确认)
  0: 1e-3
  11: 5e-4                  # Kratzert epoch-11(1-indexed); 原 {0,10,20} 会早 1 epoch 降
  21: 1e-4                  # Kratzert epoch-21
batch_size: 256
epochs: 30                 # 固定, 无早停
seq_length: 270
predict_last_n: 1
clip_gradient_norm: 1.0
seed: 100                  # 每 seed 一份 run(8 个), 见 §5

# --- data ---
forcings:
  - maurer
dynamic_inputs:            # 列名审核确认与 maurer 文件头精确匹配; 注:Maurer Tmax==Tmin(均=日均温)→ 5 列实为 4 独立 forcing, 与 Kratzert 同
  - PRCP(mm/day)
  - Tmin(C)
  - Tmax(C)
  - SRAD(W/m2)
  - Vp(Pa)
target_variables:
  - QObs(mm/d)
static_attributes:         # Kratzert 27(列名以属性 CSV 为准, R3 preflight)
  # climate ×9
  - p_mean
  - pet_mean
  - aridity
  - p_seasonality
  - frac_snow
  - high_prec_freq
  - high_prec_dur
  - low_prec_freq
  - low_prec_dur
  # topo ×3
  - elev_mean
  - slope_mean
  - area_gages2
  # veg ×5
  - frac_forest
  - lai_max
  - lai_diff
  - gvf_max
  - gvf_diff
  # soil ×8
  - soil_depth_pelletier
  - soil_depth_statsgo
  - soil_porosity
  - soil_conductivity
  - max_water_content
  - sand_frac
  - silt_frac
  - clay_frac
  # geol ×2
  - carbonate_rocks_frac
  - geol_permeability

# --- eval / logging ---
metrics:
  - NSE
# ⚠️ 不做 validation(Kratzert 无早停/无选模, 固定 30 epoch)。审核 5/5 确认:
#    `validate_n_random_basins:0 + validate_every` 会触发"全 531 basin 每 N epoch 验证一次"
#    (basetrainer.py:194-200), 是巨量无用算力, **不是关闭**。
#    关闭法 = **省略 validate_every**(basetrainer.py:193 `if validate_every is not None` → 不建 validator)。
#    故下面不写 validate_every / validate_n_random_basins。
save_weights_every: 30         # 仅存末轮(省盘)
log_tensorboard: false         # GPU/日尺度可开; 防 segfault 谨慎
log_n_figures: 0
device: cuda:0
```

**EA-LSTM 变体**:复制上文,`experiment_name: kratzert2019_ealstm_maurer_531`,`model: ealstm`。
EA-LSTM 把静态属性送 input gate,其余不变。

---

## 5. 训练执行(8 seed × 2 架构 = 16 runs)

```bash
# 单 run(本地 GPU)
python -m neuralhydrology.nh_run train \
  --config-file src/lstm_fair_531/configs/kratzert2019_cudalstm_maurer_531.yml --gpu 0

# 8 seed: 用 nh-schedule-runs 或脚本循环改 seed + experiment_name
#   seeds = [100,200,300,400,500,600,700,800]
# 评估(test 期):
python -m neuralhydrology.nh_run evaluate --run-dir <run_dir> --period test --epoch 30
```

- **HPC(河海)**:写 SLURM(`src/lstm_fair_531/hpc/`),GPU 分区;每 run 单卡。16 runs 可并行/排队。
  本地若无足够 GPU 显存(hidden 256 + batch 256 + seq 270 + 531 basins),≈ 数 GB,消费级卡可行。
- **集成**:`create_results_ensemble(run_dirs=[8 个 cudalstm], period='test', metrics=['NSE'])`
  → 逐 basin 集成 NSE;EA-LSTM 同理。
- **预计**(已据审核修正):关掉 validation 后,cudalstm 单 run 30 epoch 全 531 ≈ 1–3 h(GPU)。
  **EA-LSTM 因 Python 逐时刻循环(ealstm.py:100)显著更慢**。**串行单卡 16 runs 实际更接近 1.5–2.5 天**;
  "半天–1 天"仅在多卡/HPC 并行下成立。**8-seed 脚本务必把 seed 拼进 `experiment_name`**——否则同分钟
  run 目录名(精确到分钟,basetrainer.py:434)冲突 → 直接报错中止(:450)。

---

## 6. 公平性核对 + 风险登记(preflight 闸门,跑前必清)

| ID | 风险/核对项 | 处置 | 阻断? |
|---|---|---|---|
| **R1** | ⚠️**原判错,已纠**(审核 5/5 confirmed):LSTM 用 forcing-header area、概念模型用 `area_gages2`,两条 obs(mm/d)差一个**逐 basin 常数**(全 531: median 0.52%, max 150.6%, 37 个 >5%)。但**两管线各自 sim+obs 同尺度,且 NSE 对同缩放不变** → 各模型原生 per-basin NSE **本来就可直接比,无需统一**。原"统一 obs"方案**有害**:只换 LSTM 的 obs 为 gages2 而不同步缩放 sim,会凭空注入最高 2.5× 尺度错配、**单方面压低 LSTM**。 | **不统一 obs**;声明"所有模型对同一条 USGS cfs 打分"即可。**仅当**报告尺度敏感指标(bias / KGE-β / FHV / FLV)时,才把两管线 sim+obs 一起重建到同一 area。 | **否**(披露) |
| **R2** | ✅**审核已验证通过**:maurer 文件头列名(`PRCP(mm/day)/SRAD(W/m2)/Tmax(C)/Tmin(C)/Vp(Pa)`)与 config 精确匹配 | 无需改;preflight 降为确认 | 否 |
| **R3** | ✅**审核已验证通过**:27 属性名全部存在(`frac_snow` 非 daily,`carbonate_rocks_frac`,`p_seasonality` 均在),531 basin **零 NaN**;比 nh 自带 26-attr 示例更忠实(后者漏 p_seasonality) | 无需改 | 否 |
| **R4** | ✅**审核已验证通过**:`data/camels_us` 根下直接有 basin_mean_forcing/maurer + camels_attributes_v2.0 + usgs_streamflow,**无需 `/full`** | 用 `data/camels_us` | 否 |
| **R5** | ✅**审核已验证通过**:maurer 覆盖 1980-01-01→2008-12-31,train/test/val + seq-270 lead-in 全覆盖;val(..1989-09-30)/test(1989-10-01..)/train(1999-10..)互不重叠,无泄漏 | 无需改 | 否 |
| **R6** | ✅**已修**:审核确认 **nh 训练循环是 1-indexed**(非 0-indexed),key 0 仅初始化优化器 → 忠实值 = **{0:1e-3, 11:5e-4, 21:1e-4}**(已写入 §4);原 {0,10,20} 早 1 epoch 降 lr | 已修 | 否 |
| **R11** | ✅**审核发现**:8 seed 若同 `experiment_name` 同分钟并行启动 → run 目录名(精确到分钟,basetrainer.py:434)冲突 → 报错中止(:450) | 8-seed 脚本把 **seed 拼进 `experiment_name`**(不止改 seed) | 是 |
| **R12** | ✅**审核发现**:EA-LSTM forward 是 **Python 逐时刻循环**(ealstm.py:100),比 cudalstm 融合 `nn.LSTM` 慢得多 | cudalstm 优先(DL 上界);ealstm 次要,预留更多 GPU 时间 | 否 |
| **R7** | warmup 机制不可比:概念模型 1 年 spin-up vs LSTM 270 天序列 lead-in | **不强行对齐**(模型类内禀);论文如实披露,与 Kratzert 同 | 否(披露) |
| **R8** | 信息不对称:LSTM 有 27 静态属性 + 跨 basin 区域共享;概念模型逐 basin 标定 | 如实披露;这正是 Kratzert"区域 LSTM 仍胜逐 basin 标定"的公平框架核心 | 否(披露) |
| **R9** | 训练目标不同:LSTM 用 basin-averaged NSE\*;概念模型逐 basin NSE。**评估指标同为逐 basin NSE**。 | 披露;评估口径一致即可 | 否(披露) |
| **R10** | PET:概念模型用 PT PET;LSTM 用原始 srad/temp/vp 自学,不吃 PET。故 §1 的 PET-bias caveat 不影响 LSTM。 | 披露 | 否 |

> **公平的硬定义**(可写进论文):同 basins / 同周期 / 同 forcing(Maurer)/ 同 obs(R1 统一后)/ 同评估指标(NSE)。
> 模型类内禀差异(区域 vs 逐 basin、属性、warmup、训练目标)**如实披露,不假装抹平**——与 Kratzert 2019 立场一致。

---

## 7. 对比与分析方案(后续)

**A. 主对比(full-531 head-to-head,我们完全控制的 5 个模型)**
- 模型:LSTM-cudalstm、LSTM-ealstm、GR4J、XAJ、HBV(后三个用既有冻结 per-basin CSV)。
- **apples-to-apples 头条 = LSTM-single vs 概念-single**(概念模型是 single-best per-basin 标定);
  **8-seed 集成单列为"best-practice"次条**并明确标注,不让集成数字独占头条(审核:集成有方差缩减红利)。
- **本对比的 LSTM median 用我们自己跑出的 full-531 数**(预期 > 概念模型但 **< 0.74**,因 0.74 是 447 子集+集成),
  **绝不挪用 Kratzert 的 0.74**。
- 逐 basin NSE → median / mean;箱线图;CDF。
- 配对检验:Wilcoxon signed-rank(LSTM vs 各概念模型),报 p 值 + 胜率;**6 组配对加 Holm 多重比较校正**
  (或声明 effect-size/CI 为主推断、p 值仅描述)。
- bootstrap(basin 重采样,1e4 次)对 Δmedian 给 95% CI。
- 分 regime(humid/snow/semi-humid/arid,沿用 `camels_us_531_regime_diagnostic.md` 的分层)看 LSTM 优势在哪类最大。

**B. 文献定位(447 共同子集)**
- **447 锁 Kratzert 口径** = 5 个 published benchmark(SAC-SMA/VIC/mHM/HBV/FUSE)finite-NSE 的交集,
  **不再与我们模型的 finite 集再相交**(否则集合变样、与 0.742/0.758 不可比)。从
  `results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01/diagnostic/cross_method_per_basin_nse.csv`
  导出,**物化成一个提交进仓的 basin-id 文件**;并**断言它与 Kratzert published-finite 447 的 basin 成员一致**(不止 count=447)。
- **复现闸门(按架构分开)**:cudalstm-ens vs **0.758±0.03**,ealstm-ens vs **0.742±0.03**;落带内 → 管线忠实复刻;
  显著偏低 → 有 bug。**caveat**:Kratzert 用"更新版未正式发布的 Maurer"(加日 tmin/tmax),本仓 maurer 已含 tmin/tmax,
  故可复现到 ~0.74 但不保证 bit-exact。
- 同子集对照 published SAC-SMA 0.603 / HBV-upper 0.676 / mHM 0.666(本仓 diagnostic 独立重算 0.6028/0.6756/0.6659,吻合)。
- 注意:published SAC-SMA median **0.603**(非本仓某些文档的 0.607,见 reuse doc §1 待核)。

**C. 与三学派的关系叙事**
- ⚠️**禁止混子集**(审核 4/5 confirmed):0.74/0.758 是 **447+集成**值,GR4J 0.653 / XAJ 0.62 / HBV 0.62 是
  **full-531+single** 值,**不可同框排序**。头条 take-home 只在 **§7A 的 full-531 同集合**上画(用我们自己跑的 LSTM
  full-531 median);0.74/0.758 只留 §7B 文献定位,且永远标注子集。
- 给 531-DA 论文:一条 **DL 天花板**(我们 LSTM, full-531)+ 一条**过程模型天花板**(GR4J, full-531)。
- "HBV-lite + DA" 价值 = 把 f 的开环起点(见 reuse doc, 0.5995 或 0.617,取决于变体)推向这两条线。

**D. 交付物**
1. 16 个 run 目录 + 2 个集成结果 + per-basin NSE CSV(LSTM)。
2. 统一 obs 后重算的 5 模型 per-basin NSE 对照表(full-531 + 447 子集)。
3. 对比图(箱线/CDF/分 regime/散点 LSTM-vs-conceptual)。
4. 复现闸门报告(我们 LSTM vs Kratzert 0.74)。

---

## 8. 待决选项(给用户,默认已选,可改)

1. **架构**:默认**两者都跑**(cudalstm+static 作最强 DL 上界,ealstm 作 Kratzert 名义架构)。若只要一个 → 推荐 cudalstm+static。
2. **seq_length**:默认 **270**(Kratzert 2019 忠实)。若想蹭多 forcing 路线可 365(但本方案锁单 Maurer,270 更对齐)。
3. ~~obs 统一口径(R1)~~ **已撤销**:审核证明 NSE 比较无需统一 obs(见 §6 R1)。默认**不统一**,只声明同一 USGS cfs 源;
   仅尺度敏感指标(bias/KGE-β/FHV/FLV)才需统一 area。
4. **新 idea id**:LSTM 工作区建议登记为 **ID 18**(`src/lstm_fair_531/` + `results/18_lstm_fair_531/`),在 `draft/RESEARCH_INDEX.md` 注册。

---

## 9. 执行顺序(checklist)

- [x] preflight R2/R3/R4/R5(审核已逐项验证通过:列名/27 属性零 NaN/data_dir/日期覆盖)
- [x] ~~R1 统一 obs~~ **撤销**(NSE 比较本就公平);仅尺度敏感指标才需统一 area
- [ ] 物化 447 basin-id 文件(5-published 交集)并断言与 Kratzert 成员一致
- [ ] 写 2 份 config(cudalstm/ealstm, lr={0,11,21}, **关 validation**)+ 8-seed 脚本(**seed 拼进 experiment_name**)+ (可选)HPC SLURM
- [ ] 训练 16 runs → evaluate test → 集成(cudalstm 优先, ealstm 较慢)
- [ ] 447 复现闸门(**按架构**: cudalstm vs 0.758±0.03 / ealstm vs 0.742±0.03)→ 通过才继续
- [ ] 5 模型 per-basin NSE 对照(full-531 + 447;**无需统一 obs**)
- [ ] 配对统计(Holm 校正)+ 分 regime + 图(子集/集成口径处处标注)
- [ ] 写入 531-DA 论文的 DL 天花板参考(用 full-531 数)
```
