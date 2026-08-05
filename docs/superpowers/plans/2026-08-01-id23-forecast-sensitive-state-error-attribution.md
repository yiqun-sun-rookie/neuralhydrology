# ID23 Forecast-Sensitive State-Error Attribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Identify which of the fifteen saved state errors changes future discharge skill when each daily forecast still starts from one complete state and follows one deterministic, observation-free trajectory.

**Architecture:** Read only the sealed three-stage synthetic evidence. For the parameter-uncertainty and joint-uncertainty updated states, construct a baseline plus fifteen one-component truth replacements, a five-store truth replacement, a ten-routing-memory truth replacement, and a complete-truth oracle. Forecast every intervention with the same true stage parameters, preserve the all-day rolling-origin and same-stage target contract, and independently recompute every saved trajectory with the reference transition.

**Tech Stack:** Python 3.11, NumPy, pytest, JSON, compressed NumPy evidence packages, matched-block bootstrap statistics.

## Global Constraints

- Preserve the dirty isolated worktree; do not stage, commit, delete, overwrite, or rerun any sealed historical result.
- Use experiment identifier `g3_forecast_sensitive_state_error_attribution_v01`, one frozen config, one new output directory, and one registry row.
- Use all 540 assimilation-day origins and lead days 1 through 7; same-stage targets are primary and forecasts crossing a truth-parameter change are excluded from primary metrics.
- Every forecast uses one fifteen-element state, one true stage parameter vector, future meteorological forcing, and no future discharge observation.
- No covariance, sigma point, candidate probability, or per-candidate trajectory may enter this experiment.
- Treat one-at-a-time replacements as marginal mechanism interventions. Their effects need not add to the complete-state effect because state errors can compensate nonlinearly.
- Use the eight matched blocks as the bootstrap unit with 20,000 fixed replicates and seed 20260801.
- Call a state component a screened material contributor at a lead only when its replacement lowers root-mean-square error by at least 1 percent and the paired pointwise 95 percent interval for mean squared error has upper bound below zero. Label all such findings synthetic and exploratory; do not use them as multiplicity-controlled formal confirmation.
- Process one updated-state method and one intervention at a time; peak working memory must remain below 1 gibibyte.

---

### Task 1: Freeze intervention names and statistics

**Files:**
- Create: `docs/plans/2026-08-01-id23-forecast-sensitive-state-error-attribution-design.md`
- Create: `src/hbv_multilead_joint_uncertainty/configs/g3_forecast_sensitive_state_error_attribution_v01.json`
- Create: `test/test_hbv_forecast_sensitive_state_error.py`
- Create: `src/hbv_multilead_joint_uncertainty/forecast_sensitive_state_error.py`

**Interfaces:**
- Consumes: parameter-uncertainty state, joint-uncertainty state, same-day truth state, truth targets, same-stage mask, and fixed bootstrap indices.
- Produces: `build_state_interventions(estimated_state, truth_state) -> dict[str, np.ndarray]` and `summarize_intervention_forecasts(forecasts, truth, same_stage_mask, bootstrap_indices, method_names, intervention_names) -> dict[str, object]`.

- [x] **Step 1: Write a failing intervention contract test**

```python
def test_interventions_replace_exactly_the_named_state_slice():
    interventions = build_state_interventions(estimated, truth)
    assert tuple(interventions) == INTERVENTION_NAMES
    np.testing.assert_array_equal(interventions["truth_component__SNOWPACK"][..., 0], truth[..., 0])
    np.testing.assert_array_equal(interventions["truth_component__SNOWPACK"][..., 1:], estimated[..., 1:])
```

- [x] **Step 2: Implement nineteen frozen interventions**

Use `baseline_estimated`, fifteen `truth_component__<state name>` interventions in `STATE_NAMES` order, `truth_hydrologic_group`, `truth_routing_group`, and `truth_all_states`.

- [x] **Step 3: Write and implement statistic tests**

For each method, intervention, and lead, save root-mean-square error, matched-block mean squared error, replacement-minus-baseline mean squared error, percentile 95 percent interval, relative root-mean-square error change, and the frozen material-contributor decision.

- [x] **Step 4: Run the unit test**

Run: `python -m pytest test/test_hbv_forecast_sensitive_state_error.py -q`

Expected: all tests pass.

### Task 2: Add the guarded experiment runner

**Files:**
- Create: `src/hbv_multilead_joint_uncertainty/scripts/run_g3_forecast_sensitive_state_error_attribution.py`
- Create: `test/test_hbv_forecast_sensitive_state_error_runner.py`
- Modify: `src/hbv_multilead_joint_uncertainty/configs/g3_experiment_registry.csv`

**Interfaces:**
- Consumes: sealed `g3_ideal_gate_param_switch_v01/evidence.npz` only after exact SHA-256 validation.
- Produces: `evidence.npz`, `summary.json`, `config_snapshot.json`, `environment.json`, and `checksums.json` under the new isolated result directory.

- [x] **Step 1: Test the source hash, state method order, state names, 540 origins, seven leads, and output non-overwrite guards**

- [x] **Step 2: Reuse the validated daily-origin index and deterministic forecaster**

Select only the parameter-uncertainty and joint-uncertainty combined states. Use the target day's archived truth discharge and the origin day's true stage parameters.

- [x] **Step 3: Add a production-reference preflight**

At origins 0, 179, 180, 359, 360, and 539 for both state methods and representative interventions, require the production trajectory to match the independent reference trajectory within `1e-10`.

- [x] **Step 4: Forecast interventions sequentially and save atomic evidence**

Save every trajectory and statistic under explicit method and intervention keys. Copy the frozen config and record source/output SHA-256 values.

- [x] **Step 5: Register the run as a synthetic exploratory mechanism attribution**

Keep the registry conclusion `pending independent verification` until Task 3 passes.

- [x] **Step 6: Run runner tests**

Run: `python -m pytest test/test_hbv_forecast_sensitive_state_error_runner.py -q`

Expected: all tests pass.

### Task 3: Independently recompute every intervention

**Files:**
- Create: `src/hbv_multilead_joint_uncertainty/scripts/verify_g3_forecast_sensitive_state_error_attribution.py`
- Create: `test/test_hbv_forecast_sensitive_state_error_verifier.py`

**Interfaces:**
- Consumes: sealed source and completed evidence package.
- Produces: `independent_verification.json` without importing the production intervention or deterministic forecast modules.

- [x] **Step 1: Rebuild all nineteen state interventions directly from saved source arrays**

- [x] **Step 2: Recompute trajectories with `advance_reference_state` and `reference_routed_discharge`**

- [x] **Step 3: Recompute masks, errors, bootstrap intervals, rankings, and decision flags**

- [x] **Step 4: Require all floating arrays within `1e-10` and exact equality for labels, indices, masks, and decisions**

- [x] **Step 5: Run verifier tests**

Run: `python -m pytest test/test_hbv_forecast_sensitive_state_error_verifier.py -q`

Expected: all tests pass.

### Task 4: Run, verify, and close the experiment

**Files:**
- Create: `results/23_hbv_multilead_joint_uncertainty/g3_forecast_sensitive_state_error_attribution_v01/`
- Create: `docs/plans/2026-08-01-id23-forecast-sensitive-state-error-attribution-closure.md`
- Modify: `src/hbv_multilead_joint_uncertainty/configs/g3_experiment_registry.csv`

**Interfaces:**
- Produces: per-lead component rankings, material-contributor flags, group-replacement effects, and an explicit limit on causal interpretation.

- [x] **Step 1: Run the guarded experiment into the unused output directory**

Run: `python -m hbv_multilead_joint_uncertainty.scripts.run_g3_forecast_sensitive_state_error_attribution --config src/hbv_multilead_joint_uncertainty/configs/g3_forecast_sensitive_state_error_attribution_v01.json --output-dir results/23_hbv_multilead_joint_uncertainty/g3_forecast_sensitive_state_error_attribution_v01`

- [x] **Step 2: Run the independent verifier**

Run: `python -m hbv_multilead_joint_uncertainty.scripts.verify_g3_forecast_sensitive_state_error_attribution --result-dir results/23_hbv_multilead_joint_uncertainty/g3_forecast_sensitive_state_error_attribution_v01`

- [x] **Step 3: Apply the frozen interpretation rules**

Report which corrections are beneficial, harmful, or inconclusive at each lead; whether the five hydrologic stores or routing memory explains the short-lead ranking; and whether effects differ between parameter-uncertainty and joint-uncertainty updated states.

- [x] **Step 4: Close the registry only after independent verification passes**

Record exact sample counts, root-mean-square errors, paired intervals, source hash, result hash, runtime, and synthetic-only scope.

### Task 5: Regression and ambiguity audit

**Files:**
- Modify: `docs/superpowers/plans/2026-08-01-id23-forecast-sensitive-state-error-attribution.md`

**Interfaces:**
- Produces: a checked plan and an evidence-bounded final conclusion.

- [x] **Step 1: Run the three new test files and the existing deterministic forecast regression files**

Run: `python -m pytest test/test_hbv_forecast_sensitive_state_error.py test/test_hbv_forecast_sensitive_state_error_runner.py test/test_hbv_forecast_sensitive_state_error_verifier.py test/test_hbv_deterministic_unique_state_forecast.py test/test_hbv_deterministic_updated_state_ranking.py test/test_hbv_forecast_propagation_form_comparison.py -q`

- [x] **Step 2: Run `git diff --check` and verify the sealed source SHA-256 remains `77f84d793f18a72972e5af5f2ac4ed767645471e37da31c612ab995ecf4bbf67`**

- [x] **Step 3: Confirm no wording equates marginal one-component replacement with additive causal decomposition or real-basin proof**

- [x] **Step 4: Mark every completed checklist item and report only independently verified results**
