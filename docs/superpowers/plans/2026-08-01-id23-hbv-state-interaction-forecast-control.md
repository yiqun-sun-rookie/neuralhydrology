# HBV State-Interaction Forecast Control Implementation Plan

> **For agentic workers:** Execute this plan inline with test-first development and independent verification. Do not dispatch subagents. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Determine whether full state-and-covariance interaction improves one-through-seven-day HBV discharge forecasts relative to no state interaction when both methods use one global posterior state, the same fixed parameter vector, the same forcing, and one deterministic trajectory.

**Architecture:** Reuse the independently verified daily global-posterior states from the completed HBV state-interaction audit. Start one deterministic HBV trajectory from each method's unique global posterior at every daily origin, fixing the forecast parameter vector to `trained_center` and excluding targets that cross a synthetic truth-parameter stage boundary from primary metrics. Publish an atomic evidence package and verify it with a separate implementation that does not import the production runner or production summary module.

**Tech Stack:** Python, NumPy, pytest, JSON, CSV, SHA-256.

## Global Constraints

- This is an HBV synthetic mechanism experiment, not WALRUS evidence and not real-basin evidence.
- The only changed factor is full versus absent state-and-covariance interaction during assimilation.
- Both methods publish one posterior-probability-weighted global posterior state per day.
- Both forecasts use the identical fixed `trained_center` parameter vector, future meteorological forcing, origins, targets, and deterministic propagation.
- No model-conditioned candidate trajectory, forecast covariance, sigma point, or future discharge observation is allowed.
- Use all eight matched input blocks, all three truth scenarios, every valid daily origin, and lead days one through seven.
- Do not group the primary result by days since a truth-parameter stage boundary.
- One experiment identifier, one frozen config snapshot, one isolated output directory, and one registry row.
- Preserve the completed state-audit and ideal-truth evidence byte-for-byte.

---

### Task 1: Freeze the forecast comparison contract

**Files:**
- Create: `src/hbv_multilead_joint_uncertainty/configs/g3_fixed_process_state_interaction_controlled_forecast_v01.json`
- Create: `test/test_hbv_state_interaction_controlled_forecast_runner.py`

**Interfaces:**
- Consumes: completed state evidence SHA-256 `22f1b99ee0cf537e1aa7c9b414662c0b390510f2dc0d6b07bf538dd6dda33a04` and ideal evidence SHA-256 `77f84d793f18a72972e5af5f2ac4ed767645471e37da31c612ab995ecf4bbf67`.
- Produces: frozen configuration accepted by `validate_config(config: Mapping[str, object]) -> None`.

- [ ] **Step 1: Write a failing config test requiring HBV scope, full-versus-none method order, fixed `process_2`, fixed `trained_center`, leads one through seven, same-stage targets, no future observations, and both sealed hashes.**

```python
def test_config_is_a_single_factor_hbv_forecast_control(config):
    assert config["model_family"] == "HBV"
    assert config["state_methods"] == [
        "fully_interacting_global_posterior_state",
        "noninteracting_global_posterior_state",
    ]
    assert config["only_changed_factor"] == "assimilation state and covariance interaction"
    assert config["fixed_process_id"] == "process_2"
    assert config["fixed_forecast_parameter_id"] == "trained_center"
    assert config["lead_days"] == list(range(1, 8))
    assert config["cross_switch_policy"] == "exclude_from_primary_metrics"
    assert config["future_discharge_observations_used"] is False
```

- [ ] **Step 2: Run the test and require failure because the config does not yet exist.**

Run: `python -m pytest test/test_hbv_state_interaction_controlled_forecast_runner.py -q`

- [ ] **Step 3: Create the frozen config with experiment identifier `g3_fixed_process_state_interaction_controlled_forecast_v01`, 20,000 matched-block bootstrap replicates, seed `20260801`, and numerical tolerance `1e-10`.**

- [ ] **Step 4: Run the focused config test and require it to pass.**

### Task 2: Implement source validation and paired forecast statistics

**Files:**
- Create: `src/hbv_multilead_joint_uncertainty/state_interaction_controlled_forecast.py`
- Create: `test/test_hbv_state_interaction_controlled_forecast.py`

**Interfaces:**
- Consumes: state arrays shaped `[8, 3, 2, 540, 15]`, truth discharge shaped `[8, 3, target_day]`, same-stage mask, and bootstrap indices shaped `[20000, 8]`.
- Produces: `summarize_state_interaction_forecasts(forecasts, truth, same_stage_mask, bootstrap_indices) -> dict[str, object]` using full-minus-none paired mean-squared-error differences.

- [ ] **Step 1: Write failing tests for exact method labels, array shapes, finite values, same-stage masking, full-minus-none difference direction, per-lead root-mean-square error, and paired 95% intervals.**

```python
def test_difference_direction_is_full_minus_none():
    result = summarize_state_interaction_forecasts(
        forecasts={
            "fully_interacting_global_posterior_state": full,
            "noninteracting_global_posterior_state": none,
        },
        truth=truth,
        same_stage_mask=mask,
        bootstrap_indices=bootstrap,
    )
    np.testing.assert_allclose(
        result["block_mse_difference"],
        result["block_mse"]["fully_interacting_global_posterior_state"]
        - result["block_mse"]["noninteracting_global_posterior_state"],
    )
```

- [ ] **Step 2: Run the tests and require failure because the statistics module does not yet exist.**

Run: `python -m pytest test/test_hbv_state_interaction_controlled_forecast.py -q`

- [ ] **Step 3: Implement immutable source validation and paired statistics without importing any forecast runner.**

- [ ] **Step 4: Run the focused statistics tests and require them to pass.**

### Task 3: Implement the atomic formal runner

**Files:**
- Create: `src/hbv_multilead_joint_uncertainty/scripts/run_g3_fixed_process_state_interaction_controlled_forecast.py`
- Modify: `test/test_hbv_state_interaction_controlled_forecast_runner.py`

**Interfaces:**
- Consumes: the Task 1 config, completed state-audit evidence, ideal forcing and truth, `forecast_deterministic_state`, and Task 2 statistics.
- Produces: an unused atomic result directory containing `config_snapshot.json`, `environment.json`, `evidence.npz`, `summary.json`, and `checksums.json`.

- [ ] **Step 1: Add failing runner tests requiring exact source hashes, exact full/no-interaction source indices, identical forecast parameter vectors, one state and one trajectory per method, no covariance, and unused-output protection.**

```python
def test_runner_forbids_candidate_trajectory_forecasts(runner_source):
    assert "model_conditioned_forecast" not in runner_source
    assert "candidate_forecast_trajectories_used\": true" not in runner_source.lower()
    assert '"forecast_trajectory_count": 1' in runner_source
```

- [ ] **Step 2: Select the full and no-interaction global posterior states from the verified state evidence and select the single `trained_center` parameter vector from the ideal evidence.**

- [ ] **Step 3: Build the common daily origin-target index for leads one through seven and the same-stage primary mask.**

- [ ] **Step 4: Forecast both methods with `forecast_deterministic_state` using the same future forcing slices and store every forecast before computing statistics.**

- [ ] **Step 5: Write the five required files through a temporary directory and atomically rename only after every preflight and checksum succeeds.**

- [ ] **Step 6: Run runner and statistics tests and require them to pass.**

### Task 4: Implement independent numerical verification

**Files:**
- Create: `src/hbv_multilead_joint_uncertainty/scripts/verify_g3_fixed_process_state_interaction_controlled_forecast.py`
- Create: `test/test_hbv_state_interaction_controlled_forecast_verifier.py`

**Interfaces:**
- Consumes: the completed atomic result package and both sealed input packages.
- Produces: one immutable `independent_verification.json` with checksum, trajectory, metric, interval, label, and no-future-observation checks.

- [ ] **Step 1: Write failing tests requiring that the verifier does not import the production runner, production statistics module, or production deterministic forecast function.**

```python
def test_verifier_is_independent(verifier_source):
    assert "run_g3_fixed_process_state_interaction_controlled_forecast" not in verifier_source
    assert "state_interaction_controlled_forecast" not in verifier_source
    assert "forecast_deterministic_state" not in verifier_source
```

- [ ] **Step 2: Implement an independent deterministic HBV propagation loop from the saved origin states and fixed parameter vector.**

- [ ] **Step 3: Recompute every trajectory, common mask, per-lead metric, paired interval, and decision from raw arrays.**

- [ ] **Step 4: Verify both input hashes and every result checksum, then write `independent_verification.json` only if all maximum differences are at or below `1e-10`.**

- [ ] **Step 5: Run verifier tests and require them to pass.**

### Task 5: Execute, register, and close the HBV experiment

**Files:**
- Modify: `src/hbv_multilead_joint_uncertainty/configs/g3_experiment_registry.csv`
- Modify: `src/hbv_multilead_joint_uncertainty/HANDOFF_20260801_COMPLETE_STATE_PARAMETER_CONTROL.md`
- Create: `docs/plans/2026-08-01-id23-hbv-state-interaction-controlled-forecast-closure.md`

**Interfaces:**
- Consumes: passing focused and regression tests plus the unused registered output path.
- Produces: one independently verified HBV-only conclusion with explicit boundaries.

- [ ] **Step 1: Run focused and related regression tests before the formal experiment.**

Run: `python -m pytest test/test_hbv_state_interaction_controlled_forecast.py test/test_hbv_state_interaction_controlled_forecast_runner.py test/test_hbv_state_interaction_controlled_forecast_verifier.py test/test_hbv_state_interaction_global_posterior_audit.py test/test_hbv_deterministic_unique_state_forecast.py -q`

- [ ] **Step 2: Run the formal experiment once into `results/23_hbv_multilead_joint_uncertainty/g3_fixed_process_state_interaction_controlled_forecast_v01`.**

- [ ] **Step 3: Run the independent verifier once and require all checks to pass.**

- [ ] **Step 4: Mark the registry row completed, write the closure with full-versus-none values for every lead, and state that the result is HBV synthetic mechanism evidence only.**

- [ ] **Step 5: Update the active handoff and source terminology without changing sealed historical results or claiming WALRUS applicability.**

- [ ] **Step 6: Parse every affected JSON and CSV file, run Python syntax checks, run `git diff --check`, and record final SHA-256 hashes.**
