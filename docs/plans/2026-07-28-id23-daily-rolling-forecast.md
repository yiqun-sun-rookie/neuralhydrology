# 全阶段逐日滚动预报 Implementation Plan

> **2026-07-31 scope correction:** The multi-candidate trajectory weighting
> implemented by this historical plan is an ensemble-control experiment. The
> current primary forecast is one combined state, one explicit parameter
> readout, and one trajectory.

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 实现不读取未来流量观测的全阶段逐日滚动预报、逐预见期同阶段掩码、匹配区块统计和独立核验。

**Architecture:** 复用现有同化候选库和从同化后验出发的冻结概率预报函数，新建逐日滚动样本定义与统计模块。开发运行器只读取既有八个开发区块的封存输入；只有开发门槛通过，才允许另一套正式运行器生成全新九十六个匹配区块。

**Tech Stack:** Python、NumPy、pytest、JSON、NPZ、SHA-256。

---

### Task 1: 固定逐日滚动样本索引

**Files:**
- Create: `src/hbv_multilead_joint_uncertainty/daily_rolling_forecast.py`
- Test: `test/test_hbv_daily_rolling_forecast.py`

**Step 1: Write the failing tests**

测试必须覆盖：

- 起报日为 `180..539`，其中 `539` 仅作交叉检查；
- 预见期为 `1..7`；
- 同阶段主分析计数为 `358, 356, 354, 352, 350, 348, 346`；
- 跨第 `360` 天切换计数为 `1, 2, 3, 4, 5, 6, 7`；
- 超出第 `539` 天真值范围的计数为 `1, 2, 3, 4, 5, 6, 7`；
- 三类掩码互斥；
- 非递增预见期、错误阶段长度和越界切换日被拒绝。

**Step 2: Run test to verify it fails**

Run:
`python -m pytest test/test_hbv_daily_rolling_forecast.py -q`

Expected: FAIL because the module does not exist.

**Step 3: Implement the minimal immutable index object**

实现一个只读数据对象，保存起报日、目标日、预见期、同阶段掩码、
跨切换掩码、不可评价掩码、阶段编号和距上次切换天数。不要修改
`transition_window_forecast.py` 的既有局部窗口行为。

**Step 4: Run the focused test**

Run:
`python -m pytest test/test_hbv_daily_rolling_forecast.py -q`

Expected: PASS.

### Task 2: 实现逐预见期匹配区块统计

**Files:**
- Modify: `src/hbv_multilead_joint_uncertainty/daily_rolling_forecast.py`
- Test: `test/test_hbv_daily_rolling_forecast.py`

**Step 1: Write failing synthetic-array tests**

构造小型数组，验证：

- 每个预见期只使用其同阶段有效样本；
- 区块内先对真实参数试验和有效起报日平均；
- 自助抽样只重采样匹配区块；
- 七个预见期和两个对照共享抽样索引；
- `1%` 均方根误差边界计算正确；
- 十四项全过才允许总体保留；
- 四个固定时间层和逐偏移日统计不改变主判定。

**Step 2: Run test to verify it fails**

Run:
`python -m pytest test/test_hbv_daily_rolling_forecast.py -q`

Expected: FAIL on missing summary functions.

**Step 3: Implement the statistics**

统计函数接收三种方法的预报、真值和索引对象，输出基础平方误差、
区块均值、全阶段均方根误差、两个配对比较、时间分层和描述性逐日
曲线。禁止用 `NaN` 的全数组平均隐式决定样本。

**Step 4: Run the focused test**

Run:
`python -m pytest test/test_hbv_daily_rolling_forecast.py -q`

Expected: PASS.

### Task 3: 实现开发筛查运行器

**Files:**
- Create: `src/hbv_multilead_joint_uncertainty/configs/g3_daily_rolling_forecast_development_v01.json`
- Create: `src/hbv_multilead_joint_uncertainty/scripts/run_g3_daily_rolling_forecast_development.py`
- Test: `test/test_hbv_daily_rolling_forecast_development_runner.py`

**Step 1: Write failing contract tests**

测试配置拒绝：

- 非 `1..7` 预见期；
- 非 `180, 360` 切换日；
- 非 `180, 180, 180` 阶段长度；
- 缺少任一比较方法；
- 改动后的预报合同；
- 非匹配区块统计；
- 少于十四项的开发门槛；
- 与受保护路径重叠的输出。

**Step 2: Run test to verify it fails**

Run:
`python -m pytest test/test_hbv_daily_rolling_forecast_development_runner.py -q`

Expected: FAIL because the runner does not exist.

**Step 3: Implement the development runner**

运行器读取既有八个开发匹配区块的封存输入，逐日同化一次，并在
第 `180..539` 天保存一日至七日预报。第 `539` 天只用于既有最终
起点的精确交叉检查。输出写入新的 `.incomplete` 目录，完整性通过
后再原子替换为最终目录；拒绝覆盖任何现有目录。

**Step 4: Run focused runner tests**

Run:
`python -m pytest test/test_hbv_daily_rolling_forecast_development_runner.py test/test_hbv_daily_rolling_forecast.py -q`

Expected: PASS.

### Task 4: 实现独立开发核验器

**Files:**
- Create: `src/hbv_multilead_joint_uncertainty/scripts/verify_g3_daily_rolling_forecast_development.py`
- Test: `test/test_hbv_daily_rolling_forecast_development_verifier.py`

**Step 1: Write tamper-detection tests**

分别篡改一个预报值、一个掩码值、一个区块均值和一个散列，验证
核验器均拒绝。

**Step 2: Run test to verify it fails**

Run:
`python -m pytest test/test_hbv_daily_rolling_forecast_development_verifier.py -q`

Expected: FAIL because the verifier does not exist.

**Step 3: Implement independent recomputation**

核验器从基础预报、真值和索引数组独立重算样本计数、均方根误差、
相对变化、时间分层和开发门槛，不导入运行器的汇总函数。

**Step 4: Run verifier tests**

Run:
`python -m pytest test/test_hbv_daily_rolling_forecast_development_verifier.py -q`

Expected: PASS.

### Task 5: 运行开发筛查并执行停止门槛

**Files:**
- Create only if execution is authorized by the frozen config:
  `results/23_hbv_multilead_joint_uncertainty/g3_daily_rolling_forecast_development_v01/`

**Step 1: Run exact regression before the experiment**

Run:
`python -m pytest test/test_hbv_transition_window_forecast.py test/test_hbv_post_switch_forecast_confirmation.py test/test_hbv_post_switch_forecast_confirmation_runner.py test/test_hbv_post_switch_forecast_confirmation_verifier.py test/test_hbv_daily_rolling_forecast.py test/test_hbv_daily_rolling_forecast_development_runner.py test/test_hbv_daily_rolling_forecast_development_verifier.py -q`

Expected: all selected tests pass.

**Step 2: Verify protected hashes and resource preflight**

Expected: protected paths unchanged and resource preflight reports safe to run.

**Step 3: Run the development screen**

Run:
`python src/hbv_multilead_joint_uncertainty/scripts/run_g3_daily_rolling_forecast_development.py --repo-root . --config src/hbv_multilead_joint_uncertainty/configs/g3_daily_rolling_forecast_development_v01.json --output-dir results/23_hbv_multilead_joint_uncertainty/g3_daily_rolling_forecast_development_v01`

Expected: a new evidence package; no existing package is modified.

**Step 4: Run independent verification**

Run:
`python src/hbv_multilead_joint_uncertainty/scripts/verify_g3_daily_rolling_forecast_development.py --repo-root . --result-dir results/23_hbv_multilead_joint_uncertainty/g3_daily_rolling_forecast_development_v01`

Expected: all recomputed fields and hashes agree.

**Step 5: Apply the frozen gate**

If any of the fourteen full-stage relative root mean square error changes is
greater than `-1%`, stop with `NO-GO formal confirmation`. Do not create or run
the formal configuration.

### Task 6: 仅在开发门槛通过后准备正式确认

**Files:**
- Create conditionally: `src/hbv_multilead_joint_uncertainty/configs/g3_daily_rolling_forecast_confirmation_v01.json`
- Create conditionally: `src/hbv_multilead_joint_uncertainty/scripts/run_g3_daily_rolling_forecast_confirmation.py`
- Create conditionally: `src/hbv_multilead_joint_uncertainty/scripts/verify_g3_daily_rolling_forecast_confirmation.py`
- Test conditionally: `test/test_hbv_daily_rolling_forecast_confirmation_runner.py`
- Test conditionally: `test/test_hbv_daily_rolling_forecast_confirmation_verifier.py`

**Step 1: Freeze the fresh-seed contract**

Use exactly `96` blocks, forcing seeds `8821001..8821096`, process-noise seeds
`8822001..8822096`, observation-noise seeds `8823001..8823096`, and bootstrap
seed `8824001`.

**Step 2: Write and run contract tests**

Expected: any change to block count, seeds, masks, leads, thresholds or protected
paths fails.

**Step 3: Implement preregistration and atomic evidence writing**

Write the preregistration before simulation, refuse overwrite, snapshot source
and inputs, and verify protected hashes before finalizing the evidence directory.

**Step 4: Run formal confirmation only after a separate authorization checkpoint**

Formal execution is outside the development task. It must not start merely
because the code exists.

## Completion boundary

Tasks 1–5 complete the development decision. Task 6 is conditional. A local
seven-day post-switch advantage never counts as completion of the full-stage
problem.
