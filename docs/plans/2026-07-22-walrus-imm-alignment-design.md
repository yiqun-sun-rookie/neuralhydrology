# 设计冻结：本仓交互式多模型管线 与 MATLAB trackingIMM/trackingUKF 的跨码对齐（walrus_imm_alignment_v01）

日期：2026-07-22。用户指示："你要不要尝试把本机的 imm 和 matlab 版本的对齐"→ 做。
本文件在实现与看任何比对结果之前写定并冻结判据。

## 轮次问题（单一、可独立检验）

在投稿 MATLAB 参数实验的精确设计点上（同强迫、同真值噪声实现、同 12 候选、同初值/协方差/过程与观测噪声/无迹变换参数 α=0.6874, β=2, κ=−2、同转移保持概率 0.99），本仓 `ModifiedUnscentedFilter` + `InteractingMultipleModel`（interaction_mode="full"）能否复现 trackingUKF / trackingIMM 的状态轨迹与模型概率轨迹？

## 为什么值得做

ID23 两层审查明确未审"evidence.npz 上游（似然计算、滤波器实现）的科学正确性"。MATLAB 侧是 MathWorks 商用件 + 本轮 Level A 已审的 WALRUS 模型。对上 = Python 滤波层拿到最硬外部校验；对不上 = 首个分歧步直接定位 bug 或设计差异。纯确定性比对（全部输入与参考来自投稿 .mat 全工作区），不烧种子、不跑 MATLAB。

## 输入（只读，冻结哈希）

- `G:\github\pycharm\projects\paper-imm-variable-params\synthetic\outputs\mukf\params\10\updated_results_params_10.mat`
  SHA-256 `fd080ce0fa0f4b53ca61e19060dfba6995f94f9b53fd62cb0f8681169bec609f`
  （已证与投稿包 for_submit.7z 内同名文件逐位一致。）
  取用变量——输入：p, etpot, qobs, noise_q_truth, noise_r_truth, state0, p0, cw/cv/cg/cq (12×1), cd, cs, r, q_s_all, t1_2, t2_3, cw_truth/cv_truth/cg_truth/cq_truth；参考：states_obs, states_upd_filters (12 cell), states_pred_filters, imm_probs, states_upd_imm。
- WALRUS 方程实现依据：`tmp\external\nutstore_func_public_snapshot_20260722\`（Level A 已审）快照，移植目标函数 = walrus_st_sp + func_w_dv_def + func_dveq_dg_def + func_beta_dv_def + func_q_hs_def + func_walrus_get_pq_pv_ps + func_walrus_get_etv_ets_etact + func_walrus_pond_flood + statetran_fcn 包装守卫。

## 四道门（顺序执行，全部在看结果前冻结）

**G0 输入自洽**（不通过则中止，报告缺口）：
- qobs 与 states_obs[:, 4] 逐位相等；
- t1_2 = 1216, t2_3 = 2433, 总长 3649；
- 候选第 11、12 行 = 阶段 1、2 真参数；r = 1.5e-5；p0 = diag((0.001·state0)²)；
- q_s_all 全部 12 个 = 1e-3·diag([140,1000,4,1200,0])。

**G1 WALRUS 开环移植门**：Python 逐步重放真值轨迹（阶段切换参数 + noise_q_truth，末列加 noise_r_truth），与 states_obs 比对。
- 通过线：全 3649 步 × 5 状态 max|绝对差| ≤ 1e-8（各状态量级 0.1–1200，等效相对 ~1e-11——纯浮点顺序差异水平）。
- 不过则修移植直到过或证明 .mat 与脚本语义不符（后者=发现，如实报告）。G1 不过不得进 G2。

**G2 单滤波器对齐**（12 个独立修正无迹滤波，无交互）：对 states_upd_filters{y}（3649×5 × 12）。
- 主判据：逐滤波器记录"首个超差步" first_exceed(y) = 首个 max|Δstate| > 1e-6·max(1,|参考值|) 的步；全 12 个滤波器 first_exceed = 无 → G2 强通过。
- 若出现超差：报告 first_exceed 分布与首个分歧步的逐中间量诊断（sigma 点、先验、增益）；不允许改容差后重判。

**G3 交互式多模型对齐**：对 imm_probs（3649×12）。
- 强判据：全程 max|Δprob| ≤ 1e-6。
- 汇总判据（独立于强判据报告，四个锚点）：真子滤波器阶段 1/2 平均概率（参考 0.333 / 0.365）、首次登顶循环（6 / 120）、稳定登顶循环（724 / 560）——Python 侧重算后与 MATLAB 参考的偏差逐项列出；"稳定登顶"定义 = 概率 argmax 自该循环起保持第一直到阶段末（与 2026-07-22 对齐笔记同一定义）。

**判定分级（预冻结，报告用语）**：
1. 数值一致：G1 过 且 G2 强通过 且 G3 强判据过。
2. 结构等价：G1 过，G2/G3 有超差但 G3 四个锚点全部复现（平均概率差 ≤ 0.01、循环数差 ≤ 5）。
3. 部分等价：G1 过，锚点部分复现——逐项列出，不给总断言。
4. 不等价：G1 不过（移植修复后仍不过）或锚点多数不符——报告首个分歧步与定位到的原因。
禁止事后新增中间档。

## 已知的合法分歧源（预登记，供诊断时归因）

- Cholesky 平方根实现差（numpy lower vs MATLAB 内部 QR/upper）→ sigma 点集不同但同二阶矩；对非线性传播产生高阶差异，可能随步缓慢放大。
- trackingUKF correct 是否从先验重生成 sigma 点（文档不显式；本仓"修正"版重生成）。
- 守卫钳位（hs/hq 负值）是非光滑分支，微小数值差可在钳位触发步骤放大——诊断时优先检查分歧步是否紧邻钳位事件。
- 似然常数项/数值细节（slogdet vs 直接行列式）。

## 实现与产出约定

- 代码：`src/hbv_multilead_joint_uncertainty/walrus_port.py`（模型移植）+ `scripts/run_walrus_imm_alignment.py`（运行器，G0–G3 顺序执行）。
- TDD：`test/test_walrus_imm_alignment.py`——WALRUS 子函数用手算固定值（先红后绿）；守卫/包装语义单测；重放与滤波集成属运行器门（G1–G3），不进 pytest。
- 配置：`src/hbv_multilead_joint_uncertainty/configs/walrus_imm_alignment_v01.json`（冻结 SHA-256 `34f6d9db1ffdfacbaf0cab6b43a01d8d7267cb4d942cdafbf467a238e374a604`），运行器启动时校验输入 .mat 哈希。
- 输出：`results/23_hbv_multilead_joint_uncertainty/walrus_imm_alignment_v01/`，`.incomplete` 暂存 + 密封 + 全目录 checksums。
- 复用本仓 InteractingMultipleModel 时 interaction_mode="full"、初始概率均匀 1/12、转移矩阵 = 对角 0.99 + 非对角 0.01/11（trackingIMM 标量语义）。
- 两层独立审查：一层审方法与结果，一层从 .mat 原始数组复算比对指标。
- 范围外：noise / params_noises 两实验的对齐（若 params 对齐达"数值一致/结构等价"，后续轮可复用同一 harness 扩展，另行编号）。

## 修订记录（v01 → v02，2026-07-22，执行比对门之前）

开发预检（仅 G0 输入自洽 + G1 开环移植）发现 v01 的 G0 预期"q_s_all = 1e-3·diag"取自漂移后的脚本文本，与已发表 .mat 工作区不符——工作区实跑 q_s_truth = {**1e-6**, 1e-3, 1e-4}·diag(tmp) 且真值噪声与滤波器过程噪声都取 **cell 1**（noise_q_truth 逐列经验标准差与 sqrt(1e-6·diag) 吻合），而投稿与仓库脚本文本均写 {1e-5, 1e-3, 1e-4} 且取 cell 2。修订仅更正 G0 输入事实核对（q_s_all 期望值 + 新增噪声标准差一致性检查）；G1–G3 比对判据、容差、判定分级逐字未动，且修订时 G2/G3 比对从未执行过。v01 配置保留存档（SHA 见上）；v02 SHA-256 `2b2251989e62ef1fd45ea14bfc320943cb6abd1c9b31d022a9ab3fbec3621775`。

**顺带的实质发现（复现性缺陷，与对齐无关但须报告）**：投稿包脚本文本无法复现其随附的 .mat——照文本跑会得到过程噪声方差大 1000 倍的另一设计点。Level B 多种子重跑必须按工作区值（1e-6·diag、cell 1）而非脚本文本设定。

## 与总目标的关系

本轮是复刻对比 Level C 的聚焦版（滤波层对齐，替代"整实验移植"），同时补 ID23 审查缺口"滤波器实现未审"。不修改任何冻结证据；不动 G2（间距曲线）的种子段。
