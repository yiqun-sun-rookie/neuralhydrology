# ID23 Deterministic Unique-State Forecast Attribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Correct the unique-state forecast contract to one deterministic model trajectory, audit all fifteen state components, and determine whether forecast degradation comes from parameter readout, routing-memory state error, or the updated hydrologic state.

**Architecture:** Read only the sealed three-stage synthetic evidence and construct every daily origin directly from the saved posterior combined state. A production deterministic forecaster advances one state vector without covariance or sigma points; an independent reference implementation recomputes the same trajectories. A small four-state-source by three-parameter-source factorial isolates hydrologic-state, routing-memory, and parameter-readout effects without rerunning assimilation.

**Tech Stack:** Python 3.11, NumPy, pytest, JSON and compressed NumPy evidence packages, matched-block bootstrap statistics.

## Global Constraints

- Preserve the dirty worktree and do not commit, stage, overwrite, or rerun any sealed historical result.
- Primary origins are all 540 assimilation days; forecasts use leads 1 through 7 and the archived seven future truth days.
- The origin state is the post-assimilation state for day `t`; forecast forcing begins at day `t + 1`; target discharge is day `t + h`.
- The primary comparison excludes forecasts that cross the truth-parameter switches at days 180 and 360; cross-switch forecasts are stored only as a diagnostic.
- A deterministic single trajectory must not accept or propagate a covariance matrix, sigma points, model probabilities, or future discharge observations.
- The true-stage parameter readout is an oracle mechanism control, not an operational forecasting method.
- State accuracy must report all five hydrologic stores and all ten routing-memory states. Do not call a five-store-only comparison a complete-state result.
- Source archives must be verified by SHA-256 before use; each run gets one frozen config, one isolated output directory, and one registry row.
- Peak working memory must remain below 1 gibibyte by loading only required arrays and processing one state/parameter combination at a time.

---

### Task 1: Freeze the corrected design and failure-first tests

**Files:**
- Create: `docs/plans/2026-07-31-id23-deterministic-unique-state-attribution-design.md`
- Create: `test/test_hbv_deterministic_unique_state_forecast.py`
- Create: `src/hbv_multilead_joint_uncertainty/configs/g3_deterministic_unique_state_forecast_attribution_v01.json`

**Interfaces:**
- Consumes: sealed `g3_ideal_gate_param_switch_v01/evidence.npz` and `g3_daily_rolling_forecast_readout_development_v01/evidence.npz` only for historical-control arrays.
- Produces: a frozen 540-origin contract, source hashes, twelve deterministic method names, two historical ensemble-control names, and explicit decision rules.

- [x] **Step 1: Write tests that reject covariance and future observations**

```python
def test_deterministic_forecast_interface_has_no_covariance_or_observations():
    signature = inspect.signature(forecast_deterministic_state)
    assert tuple(signature.parameters) == (
        "state", "parameters", "future_forcing", "lead_days"
    )
```

- [x] **Step 2: Write an origin-target alignment test**

```python
def test_all_daily_origins_map_t_plus_h_without_dropping_final_origins():
    index = build_all_stage_daily_index()
    assert np.array_equal(index.origin_indices, np.arange(540))
    assert np.array_equal(index.target_indices, index.origin_indices[:, None] + np.arange(1, 8))
    assert index.target_indices[-1, -1] == 546
```

- [x] **Step 3: Write state-source and parameter-source factorial tests**

```python
def test_attribution_factorial_is_four_by_three():
    assert STATE_SOURCES == (
        "posterior_all_states", "truth_all_states",
        "posterior_hydrologic_truth_routing",
        "truth_hydrologic_posterior_routing",
    )
    assert PARAMETER_SOURCES == (
        "true_stage_parameters", "posterior_weighted_parameters",
        "maximum_posterior_parameters",
    )
```

- [x] **Step 4: Run the three tests and confirm they fail because the corrected module does not yet exist**

Run: `python -m pytest test/test_hbv_deterministic_unique_state_forecast.py -q`

Expected: collection failure for `hbv_multilead_joint_uncertainty.deterministic_unique_state_forecast`.

### Task 2: Implement deterministic propagation and complete-state metrics

**Files:**
- Create: `src/hbv_multilead_joint_uncertainty/deterministic_unique_state_forecast.py`
- Modify: `test/test_hbv_deterministic_unique_state_forecast.py`

**Interfaces:**
- Produces: `build_all_stage_daily_index() -> AllStageDailyIndex`, `forecast_deterministic_state(state, parameters, future_forcing, lead_days) -> DeterministicForecast`, `build_factorial_state_sources(...) -> dict[str, np.ndarray]`, and `summarize_complete_state_error(...) -> dict[str, np.ndarray]`.

- [x] **Step 1: Implement an immutable index for origins 0 through 539 and targets 1 through 546**

The same-stage mask is derived from the archived truth-parameter index for each truth trial, not from elapsed time since a switch.

- [x] **Step 2: Implement one direct state trajectory**

Copy the fifteen-element state, project it under the selected parameter vector, advance it once per forcing row with `ForcingTransition`, and calculate routed discharge directly from the resulting state. Do not instantiate a filter.

- [x] **Step 3: Implement the four state sources**

Use indices `0:5` for hydrologic stores and `5:15` for routing memory; hybrid states replace exactly one of those slices with truth.

- [x] **Step 4: Implement all-fifteen-state error summaries**

Save root-mean-square error by method and state, hydrologic and routing group summaries, daily origin discharge error under the true lag parameter, and matched-block mean squared errors.

- [x] **Step 5: Run unit tests**

Run: `python -m pytest test/test_hbv_deterministic_unique_state_forecast.py -q`

Expected: all tests pass.

### Task 3: Add the audited runner and correctness gates

**Files:**
- Create: `src/hbv_multilead_joint_uncertainty/scripts/run_g3_deterministic_unique_state_forecast_attribution.py`
- Create: `test/test_hbv_deterministic_unique_state_forecast_runner.py`
- Modify: `src/hbv_multilead_joint_uncertainty/configs/g3_experiment_registry.csv`

**Interfaces:**
- Consumes: the frozen config and sealed arrays after exact SHA-256 checks.
- Produces: `evidence.npz`, `summary.json`, `config_snapshot.json`, `environment.json`, `checksums.json`, and a source snapshot in `results/23_hbv_multilead_joint_uncertainty/g3_deterministic_unique_state_forecast_attribution_v01/`.

- [x] **Step 1: Test source-hash, shape, candidate-order, parameter-order, and schedule guards**

- [x] **Step 2: Add a 13,104-transition alignment gate**

For every archived transition from day 0 to 546, independently apply the target day's true parameter and forcing with `advance_reference_state`; require exact equality to `truth_deterministic_states`.

- [x] **Step 3: Add an origin-state gate**

Require the parameter-only saved combined state to equal the readout archive's posterior mean on their common origins 180 through 539 within `1e-9`.

- [x] **Step 4: Run twelve deterministic combinations sequentially**

Allocate only one `[8, 3, 540, 7]` working forecast at a time, then copy it into the final evidence payload. Do not load candidate covariance arrays.

- [x] **Step 5: Add historical controls without relabeling them**

Copy the archived full-interaction and no-state-interaction multi-trajectory forecasts only on their common origins 180 through 539 and label both as ensemble controls.

- [x] **Step 6: Register the experiment as a mechanism attribution audit**

The registry conclusion remains `pending` until independent verification passes.

- [x] **Step 7: Run runner tests**

Run: `python -m pytest test/test_hbv_deterministic_unique_state_forecast_runner.py -q`

Expected: all tests pass.

### Task 4: Independently verify every saved trajectory and statistic

**Files:**
- Create: `src/hbv_multilead_joint_uncertainty/scripts/verify_g3_deterministic_unique_state_forecast_attribution.py`
- Create: `test/test_hbv_deterministic_unique_state_forecast_verifier.py`

**Interfaces:**
- Consumes: sealed sources and the completed evidence package.
- Produces: `independent_verification.json` using `advance_reference_state` and `reference_routed_discharge`, without importing the production forecast or summary functions.

- [x] **Step 1: Recompute every deterministic trajectory through the independent reference model**

- [x] **Step 2: Recompute truth targets, masks, all-fifteen-state errors, block statistics, bootstrap intervals, and decision flags**

- [x] **Step 3: Require maximum absolute difference at or below `1e-10` and exact equality for all masks, indices, labels, and Boolean decisions**

- [x] **Step 4: Run verifier tests**

Run: `python -m pytest test/test_hbv_deterministic_unique_state_forecast_verifier.py -q`

Expected: all tests pass.

### Task 5: Run the attribution experiment and apply frozen conclusions

**Files:**
- Create: `results/23_hbv_multilead_joint_uncertainty/g3_deterministic_unique_state_forecast_attribution_v01/`
- Create: `docs/plans/2026-07-31-id23-deterministic-unique-state-attribution-closure.md`
- Modify: `src/hbv_multilead_joint_uncertainty/configs/g3_experiment_registry.csv`

**Interfaces:**
- Produces: one of four evidence-bounded causal classifications.

- [x] **Step 1: Run the experiment after all correctness gates pass**

Run: `python -m hbv_multilead_joint_uncertainty.scripts.run_g3_deterministic_unique_state_forecast_attribution --config src/hbv_multilead_joint_uncertainty/configs/g3_deterministic_unique_state_forecast_attribution_v01.json --output-dir results/23_hbv_multilead_joint_uncertainty/g3_deterministic_unique_state_forecast_attribution_v01`

- [x] **Step 2: Run independent verification**

Run: `python -m hbv_multilead_joint_uncertainty.scripts.verify_g3_deterministic_unique_state_forecast_attribution --result-dir results/23_hbv_multilead_joint_uncertainty/g3_deterministic_unique_state_forecast_attribution_v01`

- [x] **Step 3: Apply the attribution rules**

1. If truth all-state plus true parameters is not best at every lead, mark implementation or metric alignment failed and stop.
2. If posterior all-state plus true parameters beats posterior all-state plus posterior-weighted parameters at all leads, parameter readout is a demonstrated contributor.
3. If replacing posterior routing memory with truth removes the remaining gap, routing-state error is a demonstrated contributor.
4. If posterior all-state plus true parameters beats both historical ensemble controls on common origins at all leads, the prior forecast readout fully hid the updated-state advantage in this synthetic experiment.

- [x] **Step 4: Record exact root-mean-square errors, paired 95 percent intervals, sample counts, and scope limits**

### Task 6: Correct affected terminology and handoff claims

**Files:**
- Modify: `src/hbv_multilead_joint_uncertainty/forecast_readout.py`
- Modify: `docs/plans/2026-07-31-id23-daily-combined-state-error-audit.md`
- Modify: `src/hbv_multilead_joint_uncertainty/HANDOFF_20260731_SINGLE_STATE_CONTRACT_CORRECTION.md`
- Modify: `G:/github/pycharm/projects/neuralhydrology/src/hbv_multilead_joint_uncertainty/HANDOFF_20260728_DAILY_ROLLING_FORECAST_CORRECTION.md`

**Interfaces:**
- Produces: unambiguous separation between historical one-filter unscented-distribution forecasts and the corrected deterministic one-state trajectory.

- [x] **Step 1: Stop calling the historical covariance-propagating readout one deterministic trajectory**

- [x] **Step 2: State that the July 31 state audit covered five hydrologic stores, not the complete fifteen-element forecast state**

- [x] **Step 3: Add the verified attribution result and retain the real-basin and operational-parameter limits**

- [x] **Step 4: Run all targeted and existing daily-rolling regression tests, `git diff --check`, source-hash checks, and a final ambiguity search**
