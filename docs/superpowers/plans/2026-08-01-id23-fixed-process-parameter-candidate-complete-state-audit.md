# ID23 Fixed-Process Complete-State Audit Implementation Plan

> **2026-08-01 semantic correction:** The archived strings remain unchanged,
> but the three-model state is the standard fully interacting multiple-model
> method's unique global posterior. This plan compares two complete
> assimilation methods and does not isolate candidate count or interaction.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Compare the same-day fifteen-state accuracy of one fixed-parameter filter posterior with the standard fully interacting three-parameter-model global posterior while holding process noise and all observations identical and executing no forecast.

**Architecture:** Read only the sealed ideal evidence, validate the single-filter and standard full-interaction source methods, select their saved final posterior-state arrays, and score them directly against same-day truth. A separate verifier reimplements the source checks and every statistic without importing the production summary module.

**Tech Stack:** Python 3.11, NumPy, pytest, JSON, compressed NumPy evidence, matched-block bootstrap.

## Global Constraints

- Use experiment identifier `g3_fixed_process_parameter_candidate_complete_state_audit_v01` with one frozen config, one unused output directory, and one registry row.
- Preserve every historical result and all unrelated dirty-worktree changes.
- Load all 540 same-day updated states and all fifteen state components.
- Do not call a forecast function or load future forcing, forecast targets, forecast arrays, covariance arrays, sigma points, or future observations.
- Hold process covariance identifier `process_2` fixed for the one-filter and three-filter methods.
- Use 20,000 matched-block bootstrap replicates with seed 20260801.
- Publish atomically and forbid output overwrite.

---

### Task 1: Freeze the complete-state contract and tests

**Files:**
- Create: `src/hbv_multilead_joint_uncertainty/configs/g3_fixed_process_parameter_candidate_complete_state_audit_v01.json`
- Create: `src/hbv_multilead_joint_uncertainty/fixed_process_parameter_candidate_state_audit.py`
- Create: `test/test_hbv_fixed_process_parameter_candidate_state_audit.py`

**Interfaces:**
- Consumes: `[blocks, truths, methods, days, 15]` saved states, `[blocks, truths, days, 15]` truth, method names, and matched bootstrap indices.
- Produces: `summarize_complete_state_controlled_error(...) -> dict[str, object]` with per-state, grouped, and complete standardized errors.

- [x] **Step 1: Write a failure-first test for all fifteen states**

```python
def test_complete_state_summary_keeps_every_state_and_matched_block():
    result = summarize_complete_state_controlled_error(
        method_states, truth_states, method_names, state_names, bootstrap
    )
    assert result["per_state_rmse"].shape == (2, 15)
    assert result["complete_standardized_rmse"].shape == (2,)
    assert result["per_state_block_mse_difference"].shape == (blocks, 15)
```

- [x] **Step 2: Require exact method order, finite matching arrays, fifteen unique state names, valid bootstrap indices, and nonzero truth variation**
- [x] **Step 3: Implement per-state root-mean-square error, group error, equal-component standardized complete error, paired intervals, and three-way decisions**
- [x] **Step 4: Run `python -m pytest test/test_hbv_fixed_process_parameter_candidate_state_audit.py -q` and require all tests to pass**

### Task 2: Add the guarded atomic runner

**Files:**
- Create: `src/hbv_multilead_joint_uncertainty/scripts/run_g3_fixed_process_parameter_candidate_complete_state_audit.py`
- Create: `test/test_hbv_fixed_process_parameter_candidate_state_audit_runner.py`
- Modify: `src/hbv_multilead_joint_uncertainty/configs/g3_experiment_registry.csv`

**Interfaces:**
- Consumes: frozen config and sealed evidence after exact SHA-256 validation.
- Produces: `evidence.npz`, `summary.json`, `config_snapshot.json`, `environment.json`, and `checksums.json`.

- [x] **Step 1: Test rejection of changed process identifier, candidate structure, source hash, day count, state count, and existing output**
- [x] **Step 2: Select only source methods `fixed_filter` and `parameter_only`; do not load forecast-related arrays**
- [x] **Step 3: Save all decisive arrays and a summary that states mixed component outcomes without claiming forecast superiority**
- [x] **Step 4: Publish through a unique incomplete directory followed by atomic rename**
- [x] **Step 5: Run the module and runner unit tests**

### Task 3: Independently verify and close

**Files:**
- Create: `src/hbv_multilead_joint_uncertainty/scripts/verify_g3_fixed_process_parameter_candidate_complete_state_audit.py`
- Create: `test/test_hbv_fixed_process_parameter_candidate_state_audit_verifier.py`
- Create: `docs/plans/2026-08-01-id23-fixed-process-parameter-candidate-complete-state-audit-closure.md`
- Modify: `src/hbv_multilead_joint_uncertainty/configs/g3_experiment_registry.csv`

**Interfaces:**
- Consumes: sealed source and completed result package.
- Produces: `independent_verification.json` and the final evidence-bounded state conclusion.

- [x] **Step 1: Reimplement candidate validation and all state statistics without importing the production state-audit module**
- [x] **Step 2: Recompute exact arrays, labels, intervals, decisions, checksums, and summary numbers with tolerance `1e-12`**
- [x] **Step 3: Run all 540-day state audit and the independent verifier once into the unused result directory**
- [x] **Step 4: Close the registry only after `independent_verification.json` reports `status=passed`**
- [x] **Step 5: Run new tests, related state regressions, `git diff --check`, a forbidden-forecast import scan, and verify that every plan item is complete**
