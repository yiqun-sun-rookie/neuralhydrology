# 设计冻结：MATLAB 参数实验同码多种子重跑（matlab_multiseed_params_v01，复刻对比 Level B）

日期：2026-07-22。本文件在跑任何正式种子之前写定；判据与汇总口径先冻结再看数。

## 轮次问题（单一、可独立检验）

已发表 MATLAB 参数实验（WALRUS 小时步 + trackingUKF/trackingIMM，单实现 rng(1)）的"能认出"结论是否依赖这颗种子？在同一设计点上，认出时间（首次登顶 / 稳定登顶所需同化循环数）与真滤波器阶段平均概率的**跨种子分布**是什么？

## 设定（复刻已发表工作区，不是脚本文本）

跨码对齐轮（walrus_imm_alignment_v02，两层审查过）已证实：投稿/仓库脚本文本的噪声设定（q_s_truth={1e-5,1e-3,1e-4}·diag、取 cell 2）**无法复现**已发表 .mat；工作区实跑 cell 1 = **1e-6**·diag([140,1000,4,1200,0]) 且真值噪声与滤波器过程噪声均取 cell 1。本实验按工作区实值设定：

- 数据：`paper-imm-variable-params\synthetic\data\PEQ_Regge_hour.txt`（SHA-256 64e9b1b3…f605fa），窗口 2000010101–2000060101，小时步，共 3649 步；预处理/参数表用坚果云工具箱快照（`tmp\external\nutstore_func_public_snapshot_20260722\`，63 文件清单在案）+ 投稿包 `for_submit\synthetic\scripts\subfunctions\`（statetran_fcn/measure_fcn/switch_mdl，与仓库版哈希一致）。
- 真值切换：cw [600,400,500]、cv [50,30,40]、cg [1.8e7,1.6e7,1.7e7]、cq [6,3,5]；阶段边界 floor(N/3)=1216 / 2433。
- 噪声：真值过程噪声协方差 = 1e-6·diag([140,1000,4,1200,0])（Q 分量零）；观测噪声方差 r = 1e-4×0.15 = 1.5e-5；滤波器 ProcessNoise = 同一矩阵（全部 12 个）。
- 候选：每参数独立 lhsdesign(n,1)，n=10，界 cw[300,700]/cv[20,60]/cg[1.5e7,1.9e7]/cq[2,7]，附加阶段 1、2 真参数 → 12 个子滤波器。
- 滤波器：trackingUKF，α=0.6874、β=2、κ=−2，State=state0=[140,1000,4,1200,0.15]、StateCovariance=diag((0.001·state0)²)、MeasurementNoise=r；trackingIMM，TransitionProbabilities=0.99，初始概率均匀。
- 随机数抽取顺序照抄 main_params.m（含被烧掉不用的 dv/dg/hq/hs lhsdesign 四次抽取），保证与发表管线同构。
- **缩减**：只跑交互式多模型循环并记录 imm_probs；不跑 12 个独立滤波器组（发表脚本里那部分只喂 NSE 表，不进本轮问题）。

## 种子（预分配，跑前冻结）

- 正式种子：**3001001–3001024**（24 个，MATLAB `rng(seed,"twister")` 空间；与 ID23 HBV 实验已用段 990001–998012、G2 预留段 1001001 起不冲突，为避免误读特意另开 3 打头段）。
- 冒烟废弃种子：**3000999**（只验证脚本能跑通与输出形状，不进任何统计）。
- 参考种子 rng(1)：不重跑——已发表 .mat 的 imm_probs 即其输出（对齐轮已核）；其锚点（724/560 等）直接与 24 种子分布并列。

## 每种子输出（最小集）

`seed_<seed>.mat`：imm_probs (3649×12)、cw/cv/cg/cq (12×1)、seed、以及 states_obs 末列（qobs）供抽查。预计 ~0.4 MB/种子。

## 汇总口径（冻结；描述性刻画，不设通过/失败门）

对每种子用与对齐轮**同一实现**的锚点代码（`run_walrus_imm_alignment._anchor_metrics`，已入 git @73916fc）计算六锚点：阶段 1/2 的真滤波器平均概率、首次登顶循环、稳定登顶循环（定义：概率 argmax 自该循环起保持第一直到阶段末；真滤波器=阶段 1 第 11 个、阶段 2 第 12 个，1-based）。汇总报告：

1. 每指标的 min / 25 分位 / 中位 / 75 分位 / max（分位数用 numpy 默认线性插值）。
2. **删失比例**：稳定登顶从未发生（该相内认不稳）的种子数与比例——必须如实报告，不得只报已认出者的分位数。
3. rng(1) 位置评注（预冻结规则）：其锚点值落在 [min,max] 内 → "非异常"；落在四分位距外 → 报告其分位位置；落在 [min,max] 外 → "异常，单实现结论依赖种子"。仅此三档，不新增档位。
4. 与 ID23 反差句式的对齐更新：报告"稳定登顶循环 ≤ 10"的种子比例（直接回答"10 循环预算内认不稳"在此设计点的跨种子普遍性）。

## 执行与密封

- 驱动脚本：`src/hbv_multilead_joint_uncertainty/matlab/multiseed_params_driver.m`（自包含设定，不调用 P 文件与原 main 脚本；addpath 只指向哈希在案的快照/投稿包路径）。
- 逐种子由 `matlab -batch` 串行执行，输出先落 `results/23_hbv_multilead_joint_uncertainty/matlab_multiseed_params_v01.incomplete/seeds/`。
- Python 汇总 runner（新增，先失败测试后实现）：读全部 seed .mat → 锚点 → `per_seed_anchors.csv` + `anchor_distribution_summary.csv` + `final_report.md` + `environment.json` + `checksums.json` → 密封改名。
- 两层独立审查：一层审设计忠实性（驱动 vs 工作区设定）与结果；一层从 seed .mat 原始数组独立重算锚点与汇总。
- 违例即停：任何种子数值发散（NaN/Inf in imm_probs）如实记录该种子并保留，不重抽。

## 范围外

noise / params_noises 两实验的多种子版；观测噪声轴扫描；MATLAB 侧单滤波器组；修改任何冻结证据。
