# ID23 Fixed-Process Parameter-Candidate Controlled Forecast Implementation Plan

> **2026-08-01 semantic correction:** The three-model source is the standard
> fully interacting method's unique global posterior, not an optional average
> of three final states. The forecast readout is controlled, but the source
> comparison does not isolate candidate count or interaction.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Compare a single fixed-parameter filter posterior against the standard fully interacting three-parameter-model global posterior while holding process noise, forecast parameters, daily origins, forcing, forecast form, and scoring identical.

**Architecture:** Read the sealed three-stage synthetic evidence and select the saved single-filter posterior and standard fully interacting global posterior. Validate that both assimilation methods use the same `process_2` covariance, then forecast both final posterior states with the same `trained_center` parameter vector through the existing direct deterministic model. An independent reference implementation rebuilds every trajectory and statistic without importing the production deterministic forecast module.

**Tech Stack:** Python 3.11, NumPy, pytest, JSON, compressed NumPy evidence packages, matched-block bootstrap statistics.

## Global Constraints

- Preserve the dirty isolated worktree and every sealed historical result; do not stage, commit, delete, overwrite, or rerun them.
- Use experiment identifier `g3_fixed_process_parameter_candidate_controlled_forecast_v01`, one frozen config, one unused output directory, and one registry row.
- The only changed factor is one versus three fixed parameter candidates during assimilation.
- Both methods use fixed process covariance `process_2`, fixed forecast parameter vector `trained_center`, one fifteen-element origin state, one deterministic observation-free trajectory, and the same future forcing.
- Use all 540 daily origins, leads 1 through 7, same-stage primary targets, eight matched bootstrap blocks, 20,000 replicates, and seed 20260801.
- Do not load covariance arrays for forecasting or propagate candidate states, probabilities, sigma points, or future discharge observations.
- Treat the three-versus-nine candidate comparison and the later state-component intervention as non-primary diagnostics.

---

### Task 1: Freeze the controlled contract and failure-first tests

**Files:**
- Create: `docs/plans/2026-08-01-id23-fixed-process-parameter-candidate-controlled-forecast-design.md`
- Create: `src/hbv_multilead_joint_uncertainty/configs/g3_fixed_process_parameter_candidate_controlled_forecast_v01.json`
- Create: `src/hbv_multilead_joint_uncertainty/fixed_process_parameter_candidate_forecast.py`
- Create: `test/test_hbv_fixed_process_parameter_candidate_forecast.py`

**Interfaces:**
- Consumes: sealed method names, candidate identifiers, saved combined states, forcing, truth discharge, and parameter vectors.
- Produces: frozen method names `single_fixed_parameter_filter_state` and `three_parameter_candidates_combined_state`, plus exact candidate and forecast-parameter guards.
- Implements the candidate contract and statistical summary in a focused module shared by the production runner but independently reimplemented by the verifier.

- [x] **Step 1: Write a test that requires one versus three candidates and identical process identifiers**

```python
def test_candidate_contract_changes_only_parameter_candidate_count():
    contract = validate_controlled_candidate_contract(method_names, candidate_ids, candidate_counts)
    assert contract.fixed_filter_candidates == ("trained_center__process_2",)
    assert contract.parameter_candidate_process_ids == ("process_2",) * 3
```

- [x] **Step 2: Write a test that rejects different forecast parameter vectors**

```python
with pytest.raises(ValueError, match="same trained_center forecast parameters"):
    validate_common_forecast_parameter(left, right, trained_center)
```

- [x] **Step 3: Run the new test and confirm failure before implementation**

Run: `python -m pytest test/test_hbv_fixed_process_parameter_candidate_forecast.py -q`

Expected: collection failure because the runner helper does not exist.

### Task 2: Implement the guarded runner

**Files:**
- Create: `src/hbv_multilead_joint_uncertainty/scripts/run_g3_fixed_process_parameter_candidate_controlled_forecast.py`
- Create: `test/test_hbv_fixed_process_parameter_candidate_forecast_runner.py`
- Modify: `src/hbv_multilead_joint_uncertainty/configs/g3_experiment_registry.csv`

**Interfaces:**
- Consumes: frozen config and sealed evidence after exact SHA-256 validation.
- Produces: `evidence.npz`, `summary.json`, `config_snapshot.json`, `environment.json`, and `checksums.json` in the isolated output directory.

- [x] **Step 1: Implement candidate-count, candidate-identifier, method-order, source-hash, 540-origin, seven-lead, and output non-overwrite guards**
- [x] **Step 2: Select saved `fixed_filter` and `parameter_only` states and the single `trained_center` parameter vector**
- [x] **Step 3: Forecast both methods sequentially with `forecast_deterministic_state` and no covariance or candidate arrays**
- [x] **Step 4: Add a production-reference preflight at origins 0, 179, 180, 359, 360, and 539 for every block and truth trial**
- [x] **Step 5: Save overall and truth-stage-specific root-mean-square errors, block mean squared errors, paired intervals, relative changes, and frozen decisions**
- [x] **Step 6: Register the result as pending independent verification and run runner tests**

Run: `python -m pytest test/test_hbv_fixed_process_parameter_candidate_forecast.py test/test_hbv_fixed_process_parameter_candidate_forecast_runner.py -q`

Expected: all tests pass.

### Task 3: Add independent full-array verification

**Files:**
- Create: `src/hbv_multilead_joint_uncertainty/scripts/verify_g3_fixed_process_parameter_candidate_controlled_forecast.py`
- Create: `test/test_hbv_fixed_process_parameter_candidate_forecast_verifier.py`

**Interfaces:**
- Consumes: sealed source and completed result package.
- Produces: `independent_verification.json` without importing the production deterministic forecast module.

- [x] **Step 1: Rebuild candidate guards, origins, targets, masks, fixed forecast parameters, and truth targets directly from sealed evidence**
- [x] **Step 2: Recompute both complete forecast arrays with `advance_reference_state` and `reference_routed_discharge`**
- [x] **Step 3: Recompute overall and stage-specific statistics, bootstrap intervals, and decision flags**
- [x] **Step 4: Require numerical differences at or below `1e-10` and exact equality for labels, indices, masks, and Boolean decisions**
- [x] **Step 5: Run verifier tests**

Run: `python -m pytest test/test_hbv_fixed_process_parameter_candidate_forecast_verifier.py -q`

Expected: all tests pass.

### Task 4: Run, independently verify, and close

**Files:**
- Create: `results/23_hbv_multilead_joint_uncertainty/g3_fixed_process_parameter_candidate_controlled_forecast_v01/`
- Create: `docs/plans/2026-08-01-id23-fixed-process-parameter-candidate-controlled-forecast-closure.md`
- Modify: `src/hbv_multilead_joint_uncertainty/configs/g3_experiment_registry.csv`

**Interfaces:**
- Produces: the controlled one-versus-three parameter-candidate conclusion.

- [x] **Step 1: Run the guarded experiment into the unused output directory**

Run: `python -m hbv_multilead_joint_uncertainty.scripts.run_g3_fixed_process_parameter_candidate_controlled_forecast --config src/hbv_multilead_joint_uncertainty/configs/g3_fixed_process_parameter_candidate_controlled_forecast_v01.json --output-dir results/23_hbv_multilead_joint_uncertainty/g3_fixed_process_parameter_candidate_controlled_forecast_v01`

- [x] **Step 2: Run the independent verifier and require `status=passed`**
- [x] **Step 3: Report the all-stage result first and stage-specific diagnostics second**
- [x] **Step 4: Close the registry only after independent verification passes**

### Task 5: Reset context and audit ambiguity

**Files:**
- Create: `src/hbv_multilead_joint_uncertainty/HANDOFF_20260801_FIXED_PROCESS_PARAMETER_CANDIDATE_CONTROL.md`
- Modify: `src/hbv_multilead_joint_uncertainty/HANDOFF_20260731_SINGLE_STATE_CONTRACT_CORRECTION.md`
- Modify: `docs/superpowers/plans/2026-08-01-id23-fixed-process-parameter-candidate-controlled-forecast.md`

**Interfaces:**
- Produces: one authoritative continuation boundary and a checked implementation plan.

- [x] **Step 1: State that three versus nine candidates is not the parameter control experiment**
- [x] **Step 2: Mark the forecast-sensitive component experiment as a downstream diagnostic only**
- [x] **Step 3: Run new tests plus deterministic forecast regressions**

Run: `python -m pytest test/test_hbv_fixed_process_parameter_candidate_forecast.py test/test_hbv_fixed_process_parameter_candidate_forecast_runner.py test/test_hbv_fixed_process_parameter_candidate_forecast_verifier.py test/test_hbv_deterministic_unique_state_forecast.py test/test_hbv_deterministic_updated_state_ranking.py test/test_hbv_forecast_sensitive_state_error.py -q`

- [x] **Step 4: Run `git diff --check`, verify the sealed source hash, scan for ambiguous parameter-update wording, and mark all plan items complete**
