# Daily Rolling Forecast Readout Comparison Implementation Plan

> **2026-08-01 semantic correction:** The posterior-probability-weighted state
> is the standard fully interacting method's global posterior output at the end
> of assimilation. The archived comparison reconstructed that output and tested
> forecast propagation choices; it did not create a new alternative final-state
> form. Per-model trajectories are ensemble controls.

> **2026-07-31 scope correction:** The historical `current_multiple_states`
> readout is an ensemble control. The primary method is
> `posterior_unique_complete_covariance_weighted_parameters`.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在完整阶段逐日滚动预报中，公平比较模型条件状态分别起报的集合对照、标准完全交互方法的全局后验状态读出、人工等权状态对照和最大后验概率子滤波器诊断。

**Architecture:** 同化仍由现有三个完整状态交互滤波器完成；新模块只负责把同一个起报后验转换成不同的预报起点。开发运行器重放八个既有匹配区块并保存基础数组，独立核验器从保存的后验快照重新建立单一滤波器、重算预报和统计，不调用运行器的汇总代码。

**Tech Stack:** Python 3、NumPy、pytest、JSON、压缩 NPZ、SHA-256。

## Global Constraints

- 实验编号固定为 `g3_daily_rolling_forecast_readout_development_v01`。
- 只使用既有八个开发匹配区块和三个真实参数试验。
- 起报日固定为第 `180..539` 天，预见期固定为第 `1..7` 天。
- 主指标只使用起报日和目标日处于同一参数阶段的样本。
- 预报期模型概率固定，不读取未来流量观测。
- 实质改善门槛固定为均方根误差降低 `1%`。
- 自助抽样固定为 `20000` 次，并复用既有逐日滚动证据的抽样索引。
- 既有结果、配置、设计和封存证据只读。
- 不执行 Git 暂存或提交，因为用户没有授权。

---

### Task 1: Freeze the experiment contract and registry

**Files:**
- Create: `docs/plans/2026-07-28-id23-daily-rolling-forecast-readout-design.md`
- Create: `src/hbv_multilead_joint_uncertainty/configs/g3_daily_rolling_forecast_readout_development_v01.json`
- Modify: `src/hbv_multilead_joint_uncertainty/configs/g3_experiment_registry.csv`

**Interfaces:**
- Consumes: sealed daily rolling evidence and ideal synthetic evidence paths with exact SHA-256 values.
- Produces: one immutable configuration read by the runner and verifier.

- [ ] **Step 1: Write the scientific design before new method results**

Record the six readout methods, moment equations, same-stage sample counts,
paired bootstrap unit, `1%` boundary, replacement gate, general-repair gate,
protected paths, evidence requirements, and scope limit.

- [ ] **Step 2: Write the exact JSON configuration**

The configuration must contain:

```json
{
  "experiment_id": "g3_daily_rolling_forecast_readout_development_v01",
  "classification": "development_mechanism_comparison",
  "lead_days": [1, 2, 3, 4, 5, 6, 7],
  "stage_lengths": [180, 180, 180],
  "switch_days": [180, 360],
  "expected_block_count": 8,
  "expected_truth_count": 3,
  "minimum_meaningful_rmse_fraction": 0.01
}
```

- [ ] **Step 3: Add one registry row**

Use status `planned`, output root
`results/23_hbv_multilead_joint_uncertainty/g3_daily_rolling_forecast_readout_development_v01`,
and metrics path `summary.json`.

### Task 2: Implement posterior readout construction

**Files:**
- Create: `src/hbv_multilead_joint_uncertainty/forecast_readout.py`
- Test: `test/test_hbv_forecast_readout.py`

**Interfaces:**
- Consumes: `CandidateBank`, three `MethodCandidate` definitions, and lead-specific future forcing.
- Produces:
  - `posterior_moments(bank, weights) -> PosteriorMoments`
  - `weighted_parameters(candidates, weights) -> dict[str, float]`
  - `single_candidate_bank(...) -> CandidateBank`
  - `forecast_readout_variants(...) -> ForecastReadoutResult`

- [ ] **Step 1: Write failing moment tests**

Use three synthetic states and positive-semidefinite covariances. Assert exactly:

```python
expected_mean = weights @ states
expected_within = np.einsum("i,ijk->jk", weights, covariances)
expected_between = sum(
    weight * np.outer(state - expected_mean, state - expected_mean)
    for weight, state in zip(weights, states)
)
```

Reject negative, nonfinite, incorrectly shaped, or nonnormalised weights.

- [ ] **Step 2: Run the focused test and require failure**

Run:
`python -m pytest test/test_hbv_forecast_readout.py -q`

Expected: import failure because the module is not implemented.

- [ ] **Step 3: Implement immutable posterior moments**

Create a frozen dataclass containing mean state, within covariance, between
covariance, and complete covariance. Symmetrise covariance results and verify
that the minimum eigenvalue is no smaller than the scale-aware numerical
tolerance used by the sigma-point implementation.

- [ ] **Step 4: Write failing single-bank tests**

Construct a real three-candidate bank from the test parameter fixtures. Assert:

- maximum-posterior selection uses `numpy.argmax`;
- a tie selects the lowest frozen candidate index;
- one-candidate banks have probability one and a one-by-one identity matrix;
- posterior-weighted parameters equal the explicit weighted sum in
  `PARAMETER_NAMES` order;
- the unique state is projected using the chosen unique parameter vector;
- input banks remain byte-for-byte numerically unchanged.

- [ ] **Step 5: Implement readout variants**

Return forecasts for these exact keys:

```python
(
    "current_multiple_states",
    "posterior_unique_complete_covariance_weighted_parameters",
    "posterior_unique_within_covariance_weighted_parameters",
    "posterior_unique_complete_covariance_maximum_parameters",
    "maximum_posterior_candidate",
    "uniform_unique_complete_covariance_uniform_parameters",
)
```

Each unique method must build a one-candidate bank and call the existing
observation-free `forecast_from_posterior`. The current method must use the
unchanged three-candidate bank.

- [ ] **Step 6: Run focused tests**

Run:
`python -m pytest test/test_hbv_forecast_readout.py test/test_hbv_multilead_forecast.py test/test_hbv_forecast_frozen_transition.py -q`

Expected: all pass.

### Task 3: Implement generic readout statistics

**Files:**
- Modify: `src/hbv_multilead_joint_uncertainty/forecast_readout.py`
- Test: `test/test_hbv_forecast_readout.py`

**Interfaces:**
- Consumes: mapping of forecast arrays, truth, same-stage mask, days since switch, bootstrap indices, and comparison baselines.
- Produces: RMSE, block mean squared error, paired intervals, relative changes, four fixed time strata, and exact replacement and repair gates.

- [ ] **Step 1: Write failing synthetic statistic tests**

For a four-block synthetic example, verify:

- each lead uses only its own mask;
- within-block errors average across truth cases and valid origins before
  bootstrap resampling;
- all comparisons reuse the same bootstrap indices;
- the meaningful boundary equals
  `baseline_mse * ((1 - 0.01)**2 - 1)`;
- replacement requires all seven point and interval gates;
- a single failed lead forces replacement to false.

- [ ] **Step 2: Implement statistics without NaN masking**

Use explicit Boolean masks per lead. Return basic squared errors and block
means so the independent verifier can recompute every reported number.

- [ ] **Step 3: Run focused tests**

Run:
`python -m pytest test/test_hbv_forecast_readout.py -q`

Expected: all pass.

### Task 4: Implement the atomic development runner

**Files:**
- Create: `src/hbv_multilead_joint_uncertainty/scripts/run_g3_daily_rolling_forecast_readout_development.py`
- Test: `test/test_hbv_daily_rolling_forecast_readout_runner.py`

**Interfaces:**
- Consumes: frozen JSON config and sealed ideal/daily evidence.
- Produces: `config_snapshot.json`, `source_snapshot/`, `evidence.npz`,
  `summary.json`, `protected_artifact_integrity.json`, `environment.json`, and
  `checksums.json`.

- [ ] **Step 1: Write failing contract and overwrite tests**

Reject an existing output, an existing `.incomplete` directory, an output
overlapping a protected path, a wrong input hash, a changed method list, wrong
lead days, wrong stage lengths, wrong switch days, or wrong block/truth counts.

- [ ] **Step 2: Implement replay and origin capture**

For each of eight blocks and three truth cases, run complete state interaction
assimilation once through 540 days. At every origin `180..539`, save candidate
states, full covariance matrices, posterior probabilities, combined state,
combined covariance, and all six readout forecasts.

- [ ] **Step 3: Add sealed cross-checks**

Require origin probabilities, current combined forecasts, current candidate
forecasts, masks, target indices, and truth forecasts to match the sealed daily
rolling evidence within field-specific tolerances no looser than:

```python
{
    "state": 1e-9,
    "covariance": 1e-8,
    "probability": 1e-12,
    "forecast": 1e-9,
}
```

- [ ] **Step 4: Implement atomic evidence writing**

Write only to `<output>.incomplete`. On success, write the manifest and move the
directory to the final output. On failure, retain the incomplete directory with
`failure.json`; never overwrite an old directory.

- [ ] **Step 5: Run runner tests**

Run:
`python -m pytest test/test_hbv_daily_rolling_forecast_readout_runner.py -q`

Expected: all pass.

### Task 5: Implement an independent verifier

**Files:**
- Create: `src/hbv_multilead_joint_uncertainty/scripts/verify_g3_daily_rolling_forecast_readout_development.py`
- Test: `test/test_hbv_daily_rolling_forecast_readout_verifier.py`

**Interfaces:**
- Consumes: completed result directory and the config snapshot inside it.
- Produces: `independent_verification.json` with checksum, reconstruction,
  numerical-field, and decision-gate results.

- [ ] **Step 1: Write tamper tests**

Create a small evidence fixture and independently tamper one checksum, mask,
forecast value, selected candidate index, block error, and decision flag.
Every mutation must raise `ValueError`.

- [ ] **Step 2: Implement checksum and schema verification**

Reject missing files, unlisted files, nonfinite arrays, incorrect shapes,
wrong input hashes, and changed source snapshot hashes.

- [ ] **Step 3: Rebuild readout forecasts from posterior snapshots**

Without importing the runner, recreate each unique one-candidate bank from
saved states, covariances, probabilities, parameter vectors, process covariance,
and forcing. Recompute all six methods and require agreement with saved
forecasts within `1e-9`.

- [ ] **Step 4: Recompute every statistic and gate**

Independently rebuild indices, squared errors, block means, root mean square
errors, bootstrap intervals, time strata, replacement decisions, and
general-repair decisions. Do not import the production summary function.

- [ ] **Step 5: Run verifier tests**

Run:
`python -m pytest test/test_hbv_daily_rolling_forecast_readout_verifier.py -q`

Expected: all pass.

### Task 6: Execute and audit the full development comparison

**Files:**
- Create: `results/23_hbv_multilead_joint_uncertainty/g3_daily_rolling_forecast_readout_development_v01/`
- Create: `docs/plans/2026-07-28-id23-daily-rolling-forecast-readout-closure.md`
- Modify: `src/hbv_multilead_joint_uncertainty/configs/g3_experiment_registry.csv`

**Interfaces:**
- Consumes: tested code and frozen config.
- Produces: verified evidence package and one result-limited closure.

- [ ] **Step 1: Run exact regression**

Run:

`python -m pytest test/test_hbv_forecast_readout.py test/test_hbv_daily_rolling_forecast_readout_runner.py test/test_hbv_daily_rolling_forecast_readout_verifier.py test/test_hbv_daily_rolling_forecast.py test/test_hbv_daily_rolling_forecast_development_runner.py test/test_hbv_daily_rolling_forecast_development_verifier.py test/test_hbv_multilead_forecast.py test/test_hbv_forecast_frozen_transition.py test/test_hbv_post_switch_forecast_confirmation.py -q`

Expected: all pass.

- [ ] **Step 2: Run the full comparison**

Run:

`python src/hbv_multilead_joint_uncertainty/scripts/run_g3_daily_rolling_forecast_readout_development.py --repo-root . --config src/hbv_multilead_joint_uncertainty/configs/g3_daily_rolling_forecast_readout_development_v01.json --output-dir results/23_hbv_multilead_joint_uncertainty/g3_daily_rolling_forecast_readout_development_v01`

Expected: one new immutable result directory; no protected artifact changes.

- [ ] **Step 3: Run independent verification**

Run:

`python src/hbv_multilead_joint_uncertainty/scripts/verify_g3_daily_rolling_forecast_readout_development.py --repo-root . --result-dir results/23_hbv_multilead_joint_uncertainty/g3_daily_rolling_forecast_readout_development_v01 --write-report`

Expected: checksum verification, forecast reconstruction, numeric recomputation,
and decisions all pass.

- [ ] **Step 4: Apply the frozen decisions**

If no unique method passes all seven replacement gates, retain the current
multiple-state method only as the reference option. If no method passes all
seven general-repair gates against no state interaction, record that forecast
readout does not solve the full-stage degradation.

- [ ] **Step 5: Write the closure and registry status**

The closure must list exact lead-wise RMSE, relative changes, paired interval
decisions, time-stratum limits, projection frequency, integrity results, and
the scope boundary. Change the registry status from `planned` to `completed`
only after independent verification passes; otherwise use `failed`.
