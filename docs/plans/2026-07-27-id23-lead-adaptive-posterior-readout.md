# Lead-Adaptive Posterior Readout Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在不修改交互式多模型同化结构的前提下，把完整状态交互获得的正确参数识别转化为可验证的多日预报改善。

**Architecture:** 保留现有 `forecast_from_posterior()` 和所有同化逻辑；新增一个纯读出函数，对一日候选预报等权平均，对三日和七日选择同化末日最高后验候选。正式运行器复用现有三阶段真值生成、完整状态交互、无状态交互和已知真实候选参照，只新增读出、统计、证据包装和冻结判定。

**Tech Stack:** Python 3.11、NumPy、pytest、现有概念性降雨—径流模型与交互式多模型实现。

---

### Task 1: 实现纯预报读出

**Files:**
- Create: `src/hbv_multilead_joint_uncertainty/lead_adaptive_readout.py`
- Create: `test/test_hbv_lead_adaptive_readout.py`

**Step 1: Write the failing tests**

覆盖：

```python
def test_readout_uses_uniform_weights_for_one_day_and_posterior_mode_later():
    probabilities = np.array([0.1, 0.8, 0.1])
    forecasts = np.array([
        [1.0, 4.0, 7.0],
        [2.0, 5.0, 8.0],
        [3.0, 6.0, 9.0],
    ])
    result = lead_adaptive_posterior_readout(
        probabilities,
        forecasts,
        lead_days=(1, 3, 7),
        rule_by_lead={1: "uniform", 3: "highest_posterior", 7: "highest_posterior"},
    )
    np.testing.assert_allclose(result.predictions, [4.0, 5.0, 6.0])
    assert result.selected_candidate_index == 1
```

另测：

- 后验并列时选择最小索引；
- 概率归一化容差为 `1e-12`；
- 非法维度、非有限值、负概率、重复预见期和缺失规则被拒绝；
- 函数不修改输入；
- 返回的逐预见期权重能逐位重建组合预报。

**Step 2: Run tests to verify RED**

Run:

```powershell
$env:PYTHONIOENCODING='utf-8'
$env:PYTHONPATH='src'
pytest test\test_hbv_lead_adaptive_readout.py -q
```

Expected: FAIL because module/function does not exist.

**Step 3: Write minimal implementation**

实现只包含：

```python
@dataclass(frozen=True)
class LeadAdaptiveReadout:
    lead_days: np.ndarray
    predictions: np.ndarray
    weights: np.ndarray
    selected_candidate_index: int


def lead_adaptive_posterior_readout(
    final_probabilities,
    candidate_predictions,
    lead_days,
    rule_by_lead,
) -> LeadAdaptiveReadout:
    ...
```

禁止导入或调用同化、滤波、状态交互和未来观测代码。

**Step 4: Run tests to verify GREEN**

Run the Task 1 command. Expected: all Task 1 tests pass.

**Step 5: Commit**

```powershell
git add src/hbv_multilead_joint_uncertainty/lead_adaptive_readout.py test/test_hbv_lead_adaptive_readout.py
git commit -m "feat(id23): add lead-adaptive posterior readout"
```

### Task 2: 实现预注册统计和保留门槛

**Files:**
- Modify: `src/hbv_multilead_joint_uncertainty/lead_adaptive_readout.py`
- Modify: `test/test_hbv_lead_adaptive_readout.py`

**Step 1: Write the failing tests**

用小型确定数组验证：

- 新读出、完整状态交互、无状态交互、固定等权和已知真实候选的均方根误差；
- 差值定义严格为“新读出减对照”；
- 匹配区块先对三个真值取平均，再按共享索引做两万次区块自助抽样；
- 百分之一均方根误差改善和损害边界转换为平方误差倍率 `-0.0199` 和 `+0.0201`；
- 三日和七日归一化平方误差复合指标；
- 最高后验候选正确率；
- 五项保留门槛逐项可触发，任何一项失败时总判定为不保留。

**Step 2: Run tests to verify RED**

Run:

```powershell
$env:PYTHONIOENCODING='utf-8'
$env:PYTHONPATH='src'
pytest test\test_hbv_lead_adaptive_readout.py -q
```

Expected: new statistics tests fail because summarizer is absent.

**Step 3: Write minimal implementation**

新增：

```python
def summarize_lead_adaptive_readout(
    forecasts,
    truth_forecasts,
    final_probabilities,
    final_true_candidate_indices,
    lead_days,
    bootstrap_replicates,
    bootstrap_seed,
    minimum_meaningful_rmse_fraction,
):
    ...
```

保存原始平方误差、逐区块差、共享自助索引、区间、边界、候选索引和每项门槛。

**Step 4: Run tests to verify GREEN**

Run the Task 2 command. Expected: all Task 1–2 tests pass.

**Step 5: Commit**

```powershell
git add src/hbv_multilead_joint_uncertainty/lead_adaptive_readout.py test/test_hbv_lead_adaptive_readout.py
git commit -m "feat(id23): add lead-adaptive retention gates"
```

### Task 3: 实现正式运行器与证据包装

**Files:**
- Create: `src/hbv_multilead_joint_uncertainty/scripts/run_g3_lead_adaptive_readout.py`
- Create: `test/test_hbv_lead_adaptive_readout_runner.py`

**Step 1: Write the failing tests**

测试运行器必须：

- 在读取科学输入前拒绝错误的预报合同和读出规则；
- 拒绝覆盖正式目录、未完成目录、预注册文件和失败旁证；
- 确认三十二个区块和所有种子唯一；
- 调用现有 `run_three_stage_switching_validation()` 生成新真值；
- 通过现有 `compare_interaction_arms()` 得到完整状态交互、无状态交互、固定等权和已知真实候选；
- 从完整状态交互保存的逐候选预报和同化末日概率重建当前基线；
- 新读出不读取未来观测；
- 保存配置快照、预注册、资源检查、环境、输入表、原始证据、汇总、受保护文件前后哈希、源码快照和校验清单；
- 打包失败时只留下 `.incomplete` 与失败记录，不伪装成正式结果。

**Step 2: Run tests to verify RED**

Run:

```powershell
$env:PYTHONIOENCODING='utf-8'
$env:PYTHONPATH='src'
pytest test\test_hbv_lead_adaptive_readout_runner.py -q
```

Expected: FAIL because runner does not exist.

**Step 3: Write minimal implementation**

复用现有加载、资源检查、环境记录、长路径哈希和原子目录替换函数；不得复制或改写滤波器和交互算法。

正式证据至少包含：

```text
block_ids
forcing/process/observation seeds
lead_days
truth_forecasts
full_posterior_forecasts
full_candidate_forecasts
full_final_probabilities
none_posterior_forecasts
uniform_forecasts
oracle_forecasts
lead_adaptive_forecasts
lead_adaptive_weights
selected_candidate_indices
true_candidate_indices
all squared errors
shared bootstrap indices and summaries
```

**Step 4: Run tests to verify GREEN**

Run the Task 3 command. Expected: all runner tests pass.

**Step 5: Commit**

```powershell
git add src/hbv_multilead_joint_uncertainty/scripts/run_g3_lead_adaptive_readout.py test/test_hbv_lead_adaptive_readout_runner.py
git commit -m "feat(id23): package lead-adaptive confirmation"
```

### Task 4: 冻结配置、登记和合同测试

**Files:**
- Create: `src/hbv_multilead_joint_uncertainty/configs/g3_lead_adaptive_readout_param_switch_v01.json`
- Modify: `src/hbv_multilead_joint_uncertainty/configs/g3_experiment_registry.csv`
- Create: `test/test_hbv_lead_adaptive_readout_config_contract.py`

**Step 1: Audit seed availability**

Run repository-wide exact integer search for all proposed forcing、process、observation and bootstrap seeds. Any collision requires replacing the entire seed family before writing the config.

**Step 2: Write failing contract tests**

Tests freeze:

- experiment ID、purpose、design、implementation plan；
- exact rule map `1 -> uniform, 3 -> highest_posterior, 7 -> highest_posterior`；
- thirty-two unique matched blocks；
- new seed families；
- unchanged parameter/process/observation sources and hashes；
- unchanged 45-day warmup、three 180-day stages、three leads and transition stay probability；
- five retention gates；
- every historical result and current config as protected paths；
- one exact preregistered registry row。

**Step 3: Run tests to verify RED**

Run:

```powershell
$env:PYTHONIOENCODING='utf-8'
$env:PYTHONPATH='src'
pytest test\test_hbv_lead_adaptive_readout_config_contract.py -q
```

Expected: FAIL until config and registry row exist.

**Step 4: Add config and registry row**

Use one new experiment ID and one output directory:

```text
g3_lead_adaptive_readout_param_switch_v01
results/23_hbv_multilead_joint_uncertainty/g3_lead_adaptive_readout_param_switch_v01
```

**Step 5: Run tests to verify GREEN**

Run Task 4 tests and all Task 1–3 tests.

**Step 6: Commit preregistration**

```powershell
git add docs/plans/2026-07-27-id23-lead-adaptive-posterior-readout-design.md docs/plans/2026-07-27-id23-lead-adaptive-posterior-readout.md src/hbv_multilead_joint_uncertainty/configs/g3_lead_adaptive_readout_param_switch_v01.json src/hbv_multilead_joint_uncertainty/configs/g3_experiment_registry.csv test/test_hbv_lead_adaptive_readout_config_contract.py
git commit -m "chore(id23): preregister lead-adaptive confirmation"
```

### Task 5: 运行开发重建和正式确认

**Files:**
- Create only ignored evidence under `results/23_hbv_multilead_joint_uncertainty/`

**Step 1: Reconstruct the frozen development result**

Read the frozen state-weight evidence and verify exact development metrics:

```text
current full posterior weighting: 1.4814167683 / 2.7462113479 / 6.6978875722
lead-adaptive readout:           1.23202051   / 2.74197389   / 6.56449110
```

This is identity verification only; do not use it for formal gates.

**Step 2: Run full preflight and relevant tests**

Run all new tests plus the existing forecast、interaction、synthetic-truth and state-weight suites. Require zero failures.

**Step 3: Execute exactly one formal run**

Run:

```powershell
$env:PYTHONIOENCODING='utf-8'
$env:PYTHONPATH='src'
python -m hbv_multilead_joint_uncertainty.scripts.run_g3_lead_adaptive_readout `
  --repo-root . `
  --config src/hbv_multilead_joint_uncertainty/configs/g3_lead_adaptive_readout_param_switch_v01.json `
  --output-dir results/23_hbv_multilead_joint_uncertainty/g3_lead_adaptive_readout_param_switch_v01
```

Never relaunch when output、`.incomplete`、preregistration or process liveness is uncertain.

**Step 4: Verify formal package**

Require:

- process exit code zero；
- stderr empty；
- final directory present and `.incomplete` absent；
- config hash and inner/outer preregistration exact；
- all checksum entries present with no extras or mismatches；
- protected paths unchanged；
- numeric arrays finite；
- all cross-checks passed。

### Task 6: 独立复算与结案

**Files:**
- Create: `src/hbv_multilead_joint_uncertainty/scripts/verify_g3_lead_adaptive_readout.py`
- Create: `test/test_hbv_lead_adaptive_readout_verifier.py`
- Create: `docs/plans/2026-07-27-id23-lead-adaptive-posterior-readout-closure.md`
- Modify: `src/hbv_multilead_joint_uncertainty/configs/g3_experiment_registry.csv`

**Step 1: Write verifier tests first**

Verifier只能读取 `evidence.npz`、`config_snapshot.json` 和 `checksums.json`；不得调用项目汇总函数。篡改任一候选索引、组合预报、自助索引、区间或校验值都必须失败。

**Step 2: Implement and run independent verifier**

独立重算：

- 新读出权重和预报；
- 五种方法均方根误差；
- 每个配对差和共享区块自助区间；
- 百分之一实用边界；
- 三日、七日复合指标；
- 候选选择正确率；
- 五项保留门槛与最终判定。

**Step 3: Update registry and closure**

只有正式包和独立复算都通过后，才把登记状态改为 `completed`。结案必须区分：

- 事实：正式数字与门槛；
- 推断：为什么短时平均、长时选择有效；
- 未知：是否能推广到其他噪声、候选间距和实际流域。

**Step 4: Run final verification**

Run all new tests, the 259-test baseline suite, `git diff --check`, package checksums and independent verifier.

**Step 5: Commit**

```powershell
git add src/hbv_multilead_joint_uncertainty/scripts/verify_g3_lead_adaptive_readout.py test/test_hbv_lead_adaptive_readout_verifier.py docs/plans/2026-07-27-id23-lead-adaptive-posterior-readout-closure.md src/hbv_multilead_joint_uncertainty/configs/g3_experiment_registry.csv
git commit -m "phase(id23): close lead-adaptive confirmation"
```

### Task 7: 安全合并

**Files:**
- No new source files.

**Step 1: Review all commits and tracked paths**

Confirm every changed path belongs to this experiment and the feature worktree is clean.

**Step 2: Create a clean temporary integration worktree**

Merge the feature branch into the exact current `migration/reorg-v1` commit, copy only required ignored inputs, and run the complete relevant test suite.

**Step 3: Check dirty-main overlap**

Require exact and parent/child path intersection of feature changes with current tracked dirty and untracked paths to be zero.

**Step 4: Fast-forward the dirty main worktree**

Only after Step 3 passes, fast-forward `migration/reorg-v1`. Copy the new ignored formal evidence through a staging directory, verify a canonical path/size/hash manifest, then move without overwrite.

**Step 5: Final audit**

Confirm:

- main branch points to the merge commit；
- merged paths have zero overlap with remaining dirty paths；
- formal evidence and feature evidence match per file；
- temporary integration worktree is removed；
- feature worktree and formal evidence remain available until handoff。
