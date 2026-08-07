# ID26 v09 主训练阶段：实现计划（分阶段）

**授权（2026-08-07）：** 批准版本09主训练阶段的代码实现；不批准训练、正式预测或评分。

**上游状态：** 严格嵌套阶段已在 HPC 通过（训练 job 201718 / 审核 job 201740，
`maximum_reference_difference = 0.0`）。主授权 `A09-TRAIN-01` 要求的 8 项前置里 7 项已存在，
第 8 项 `state_diagnostics_preregistration` 文档也在。**缺的只有代码。**

**规格来源：** `docs/superpowers/plans/2026-07-31-historical-multiscale-formal-v09-training-stage.md`
的 Task 5（冻结顺序 + 单运行训练器 + 串行编排器）与 Task 6（独立审核 + 状态诊断 + 总封存）。
本文件不重写规格，只记录分阶段落地顺序与每阶段的完成判据。

## 为什么分阶段

Task 5+6 合计 7 个生产模块 + 6 个测试文件，且含多项高难约束（两个独立 GPU 子进程产出一致
SHA-256、同随机数三模型逐轮排列哈希一致、历史门第 1/3 步梯度健康、1,745,928 键状态诊断、
总封存绑定 12 类哈希）。一次性交付无法保证质量，因此拆成 5 个阶段，每阶段独立可测、可提交。

## 阶段

### S1 冻结运行顺序（本阶段）

- 产出：`src/26_historical_band_experts/configs/formal_v09_run_order.json`
- 产出：`train_formal_v09.py` 中的 `validate_run_order_v09` 与 dropout 随机数流helpers
- 判据：验证器证明恰 24 项、三族各 8 项、八随机数各 3 次、无重复 run_id、
  且与计划表逐项一致；任何交换/缺失/重复/改名都失败。顺序必须与
  `stage_authorization_v09.MAIN_ALLOWED_RUNS` 完全一致（两处独立冻结，互为交叉校验）。
- 不需要 GPU，本地跑测试。

### S2 单运行训练器 `train_formal_v09.py`

- 复用严格嵌套的 `epoch_order_v09` / `load_training_batch_v09` / 检查点与封存模式。
- 新增：单模型训练步、按 variant 取 dynamic（continuous 需要 `history` 键）、
  历史门第 1 步为 0 且梯度有限、第 3 步前历史编码器出现非零梯度。
- 判据：参数量 297,217 / 595,198 / 596,737；30 轮 204,630 步；同随机数三模型逐轮排列哈希相同。

### S3 资源预检 `resource_preflight_formal_v09.py`

- 四种工作负载 × 两个一次性 GPU 子进程，数组哈希一致（峰值显存除外）。
- 子进程拒绝任何正式输入/输出路径。**需要 GPU → 测试在 HPC 跑。**

### S4 串行编排器 `run_formal_training_v09.py`

- 消费 `A09-TRAIN-01`，按冻结顺序逐项起子进程；父目录按模型族分
  `classic/` `capacity/` `continuous/`，最终目录 `seed_<seed>`，临时 `.building`，失败 `.failed`。
- 失败即停、不重试、不删已完成运行、写 `training_attempt_01.failure.json`。
- **必须能断点续跑**（34 小时跨多个 SLURM 作业）。

### S5 审核与总封存（Task 6）

- `audit_formal_training_v09.py` / `state_diagnostics_formal_v09.py` /
  `audit_state_diagnostics_formal_v09.py`
- 判据见原规格 Task 6 Step 1 的 22 条拒绝清单。

## 硬约束（每阶段都适用）

- 不训练、不生成正式预测、不评分、不读正式评价期观测。
- 不修改冻结协议、封存输入、严格嵌套已封存产物。
- 不动 `nh_final` conda 环境（a02 / id05 在用）。
- GPU 测试一律走 HPC channel `id26-v09-strict`，落点 `~/v09_strict`。

## 状态

- [x] S1 冻结运行顺序
- [x] S2 单运行训练器
- [x] S3 资源预检（代码 + CPU 测试；GPU 双进程一致性待 HPC 验）
- [ ] S4 串行编排器
- [ ] S5 审核与总封存
