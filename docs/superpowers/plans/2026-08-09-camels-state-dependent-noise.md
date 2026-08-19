# CAMELS-US State-Dependent Filter Noise Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an auditable lower-groundwater state-dependent filter process covariance and filter observation-variance sensitivity without changing the synthetic truth or generated observations.

**Architecture:** Extend only the CAMELS-US switching confirmation runner. Every parameter candidate receives the same daily process covariance, computed from the previous combined posterior advanced once with the center candidate and current forcing; this preserves the rule that candidates differ only in soil-storage capacity. Fixed process covariance remains the default and its numerical calculation path is unchanged; newly generated probability files contain additional provenance fields.

**Tech Stack:** Python, NumPy, pandas, pytest, existing modified unscented filter and interacting multiple-model estimator.

## Global Constraints

- Write only inside `G:\wt\camels-rising`; the main neuralhydrology checkout is read-only.
- Use design seeds `{0,1}` only; do not use validation seeds `{2,3}`.
- Keep synthetic truth noise, generated observations, forcing, candidate bank, switch schedule, and event rule unchanged.
- Do not freeze v02, commit, or start a 531-basin validation run in this task.
- Run experiments sequentially with two workers and unique output roots.
- Treat all results as exploratory parameter-identification evidence only.

---

### Task 1: Implement explicit filter-noise builders

**Files:**
- Modify: `src/camels_switch_confirmation/g2_switch_confirmation.py`
- Test: `test/test_camels_switch_confirmation.py`

**Interfaces:**
- Consumes: `SLZ_LOGNORMAL_SIGMA`, `N_STATE`, and existing fixed covariance builder.
- Produces: `build_state_dependent_lower_groundwater_covariance(lower_groundwater_state: float, variance_multiplier: float) -> np.ndarray` and `build_filter_observation_covariance(sigma_obs: float, variance_multiplier: float) -> np.ndarray`.

- [x] **Step 1: Write failing covariance tests**

```python
def test_state_dependent_covariance_matches_lognormal_first_two_moments():
    actual = build_state_dependent_lower_groundwater_covariance(100.0, 1.0)
    expected = np.zeros((15, 15))
    expected[4, 4] = 100.0**2 * np.expm1(0.02**2)
    np.testing.assert_allclose(actual, expected, rtol=1e-14, atol=0.0)

def test_filter_observation_covariance_multiplier_scales_variance_not_sigma():
    np.testing.assert_array_equal(
        build_filter_observation_covariance(0.5, 2.0), np.array([[0.5]]))
```

- [x] **Step 2: Run the focused tests and verify import failure**

Run: `python -m pytest -q test/test_camels_switch_confirmation.py`

Expected: collection fails because the two builders do not exist.

- [x] **Step 3: Implement validation and moment-matched builders**

```python
def build_state_dependent_lower_groundwater_covariance(lower_groundwater_state, variance_multiplier):
    state = float(lower_groundwater_state)
    multiplier = float(variance_multiplier)
    if not np.isfinite(state) or state < 0.0:
        raise ValueError("lower-groundwater state must be finite and nonnegative")
    if not np.isfinite(multiplier) or multiplier <= 0.0:
        raise ValueError("process-variance multiplier must be finite and positive")
    covariance = np.zeros((N_STATE, N_STATE), dtype=np.float64)
    covariance[4, 4] = multiplier * np.expm1(SLZ_LOGNORMAL_SIGMA**2) * state**2
    return covariance

def build_filter_observation_covariance(sigma_obs, variance_multiplier):
    sigma = float(sigma_obs)
    multiplier = float(variance_multiplier)
    if not np.isfinite(sigma) or sigma <= 0.0:
        raise ValueError("observation sigma must be finite and positive")
    if not np.isfinite(multiplier) or multiplier <= 0.0:
        raise ValueError("observation-variance multiplier must be finite and positive")
    return np.array([[multiplier * sigma**2]], dtype=np.float64)
```

- [x] **Step 4: Run focused tests**

Run: `python -m pytest -q test/test_camels_switch_confirmation.py`

Expected: all tests pass.

### Task 2: Thread noise modes through the runner

**Files:**
- Modify: `src/camels_switch_confirmation/g2_switch_confirmation.py`
- Test: `test/test_camels_switch_confirmation.py`

**Interfaces:**
- Consumes: the two Task 1 covariance builders.
- Produces: command-line options `--q-mode`, `--q-state-multiplier`, and `--filter-r-multiplier`; probability-file metadata and summary fields with the same names.

- [x] **Step 1: Write failing common-covariance and metadata-path tests**

```python
def test_assign_common_process_covariance_copies_one_matrix_to_every_filter():
    estimator = SimpleNamespace(filters=[SimpleNamespace(), SimpleNamespace()])
    covariance = build_state_dependent_lower_groundwater_covariance(80.0, 1.0)
    assign_common_process_covariance(estimator, covariance)
    np.testing.assert_array_equal(estimator.filters[0].process_covariance, covariance)
    np.testing.assert_array_equal(estimator.filters[1].process_covariance, covariance)
    assert estimator.filters[0].process_covariance is not estimator.filters[1].process_covariance

def test_fixed_covariance_default_remains_existing_value():
    expected = build_process_covariance(PARAMETERS, 1e-7)
    actual = build_filter_process_covariance(PARAMETERS, 1e-7, "all_hydrologic_states")
    np.testing.assert_array_equal(actual, expected)
```

- [x] **Step 2: Add command-line and worker arguments**

Use `--q-mode` choices `fixed` and `lower_groundwater_state_proportional`, default `fixed`; use positive-float defaults of `1.0` for both multipliers. Reject the state-proportional mode unless `--q-structure lower_groundwater_state_only`.

- [x] **Step 3: Update the daily covariance before every filter step**

For the state-proportional mode, after assigning current forcing, advance `estimator.state` once through the center transition, compute the moment-matched covariance from its lower-groundwater state, and call `assign_common_process_covariance(estimator, covariance)` before `estimator.step()`. The helper validates a finite symmetric `(15, 15)` matrix and assigns `covariance.copy()` to each filter. Save the applied lower-groundwater variance for every day. For fixed mode, retain the current code path and save its constant lower-groundwater variance.

- [x] **Step 4: Preserve provenance in each output**

Save `filter_q_mode`, `filter_q_state_multiplier`, `filter_observation_variance_multiplier`, and `filter_process_lower_groundwater_variance` in every probability file and mirror scalar fields in `g2_summary.json`.

- [ ] **Step 5: Run focused and existing preflight tests**

Run: `python -m pytest -q test/test_camels_switch_confirmation.py test/test_hbv_joint_uncertainty_preflight.py`

Expected: all tests pass.

Current result: the focused test file passes all 12 tests. The existing joint-uncertainty preflight has one passing test and nine setup errors because the worktree lacks the pre-existing external result table `results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01/summary/hbv_lite_cma_FINAL_pt_v1_warmup_local_full.csv`; no failure reached the implementation under test.

### Task 3: Run state-dependent design screens

**Files:**
- Update: `docs/plans/2026-08-08-camels-noise-search-registry-v01.csv`
- Create: unique result directories and logs under the existing result and `tmp` roots.

**Interfaces:**
- Consumes: state-proportional mode and the fixed 50-basin reference at `3e-8`.
- Produces: NP01, NP02, and NP03 artifacts for variance multipliers `1`, `0.25`, and `4`, respectively.

- [x] **Step 1: Run one-basin smoke cases sequentially**

Run each multiplier with `--limit 1 --workers 1`; require 2/2 success, 12 event decisions, zero truth clips, finite normalized probabilities, and exact truth equality with the fixed reference.

- [x] **Step 2: Run 50-basin screens sequentially**

Run NP01, NP02, and NP03 with `--limit 50 --workers 2`, unique output tags, standard-output logs, and standard-error logs. Abort the queue on the first failure or pre-existing output directory.

- [x] **Step 3: Independently compare results**

Require 100/100 successful tasks and 600 event decisions per setting. Apply the registered selection rule: overall pass rate at least `61.83%`; then maximize the minimum of six directed-transition pass rates; then minimize post-burn-in multiclass Brier score; then maximize overall pass rate.

### Task 4: Run observation-variance sensitivity at the selected process model

**Files:**
- Update: `docs/plans/2026-08-08-camels-noise-search-registry-v01.csv`
- Create: NR01 and NR02 result directories and logs.

**Interfaces:**
- Consumes: the selected process model from Task 3.
- Produces: filter observation-variance multiplier sensitivity at `0.5` and `2.0` with actual generated observations unchanged.

- [x] **Step 1: Run both sensitivity settings sequentially on 50 basins**

Use the same process model, candidates, truth, observations, and seeds as the selected Task 3 setting. Require 100/100 successes and exact truth equality.

- [x] **Step 2: Report sensitivity without retuning the primary configuration**

Compare event metrics, worst direction, Brier score, and negative log probability. Do not select a deliberately mismatched observation variance as primary solely because it improves the event threshold score.

### Task 5: Stop at the pre-freeze decision gate

**Files:**
- Read: all Task 3 and Task 4 artifacts.
- Do not modify: v02 frozen configuration, candidate bank, or validation seed policy.

**Interfaces:**
- Consumes: all exploratory noise screens.
- Produces: one recommended filter-noise configuration and an explicit GO/HOLD recommendation for the later 531-basin design confirmation.

- [x] **Step 1: Separate fact, inference, and unknowns**

Report only parameter-identification evidence. Mark all seed `{0,1}` values exploratory; state that state accuracy, forecast value, real-observation value, and seed `{2,3}` validation remain unknown.

- [x] **Step 2: Stop without freezing or validation**

Do not launch the final 531-basin configuration or seed `{2,3}` run until the user reviews the pre-freeze recommendation.
