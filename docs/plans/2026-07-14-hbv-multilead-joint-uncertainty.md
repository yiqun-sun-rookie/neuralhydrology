# HBV Multi-Lead Joint-Uncertainty Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build and independently verify a frozen daily one-, three-, and seven-day diagnostic hindcast comparing five
state-updating and uncertainty treatments on sixteen unseen, statically stratified United States basins.

**Architecture:** Add an isolated `src/hbv_multilead_joint_uncertainty` package that consumes the existing verified
fifteen-state adapter without changing it. A preparation phase freezes basin, parameter, noise, and input contracts from
static attributes and calibration-period data; a separate evaluation phase consumes only the frozen contract and writes
an independently verifiable result package.

**Tech Stack:** Python 3.11, NumPy, SciPy, pandas, pytest, psutil, existing HBV-lite and modified unscented-filter code.

---

The user forbids staging, commits, pushes, and overwriting results. Replace every commit checkpoint with a fresh focused
test, scoped status inspection, and recorded audit note.

### Task 1: Freeze the forecast chronology contract

**Files:**
- Create: `test/test_hbv_multilead_forecast.py`
- Create: `src/hbv_multilead_joint_uncertainty/__init__.py`
- Create: `src/hbv_multilead_joint_uncertainty/forecast.py`

**Steps:**
1. Write failing tests for updated state at date `t`, forcing from `t+1`, labels at `t+1`, `t+3`, and `t+7`, identical
   origin sets, no future-flow argument, and no mutation of the continuing filter bank.
2. Run the focused test and confirm each failure is caused by the absent forecast bridge.
3. Implement forecast-only filter and interacting-bank steps on a copied bank, preserving process covariance and
   probability transitions without likelihood updates.
4. Add a sentinel test that changes every future discharge and proves the saved origin forecast is bitwise unchanged.
5. Run the focused test and the existing 74-test suite.

### Task 2: Define exact input, parameter, and noise contracts

**Files:**
- Create: `test/test_hbv_multilead_contracts.py`
- Create: `src/hbv_multilead_joint_uncertainty/contracts.py`
- Create: `src/hbv_multilead_joint_uncertainty/selection.py`
- Create: `src/hbv_multilead_joint_uncertainty/configs/base_v01.json`

**Steps:**
1. Write failing tests for the three physical inputs, units, derivations, availability labels, parameter names and units,
   full covariance diagonals, calibration-only date bounds, unique candidates, and file hashes.
2. Implement deterministic local parameter sampling and the development-period equivalence screen.
3. Implement robust residual scale, process/observation noise grid scoring by pre-observation log likelihood, and three
   unique neighboring process scales.
4. Compare the former bound-directed vectors with the selected equivalence vectors using development data only.
5. Run focused tests and save an audit table; do not read evaluation observations during preparation.

### Task 3: Freeze sixteen unseen basins without evaluation-performance selection

**Files:**
- Create: `test/test_hbv_multilead_basin_selection.py`
- Create: `src/hbv_multilead_joint_uncertainty/basins.py`
- Create: `src/hbv_multilead_joint_uncertainty/configs/pilot_six_basins.csv`

**Steps:**
1. Write failing tests for eligibility, four climate strata crossed with two static-response and two area strata,
   deterministic salted hashing, zero overlap with all development basins, complete input windows, area consistency,
   meteorological plausibility, and
   prohibition of evaluation metrics as selector inputs.
2. Implement fixed climate/response/area thresholds, deterministic salted selection, and Maurer-versus-Daymet quality gates.
3. Generate the proposed sixteen-basin table, then independently recompute it from raw inputs without reading evaluation
   discharge or model scores.
4. Freeze the reviewed table under a new versioned filename and checksum.

### Task 4: Implement the five matched methods

**Files:**
- Create: `test/test_hbv_multilead_methods.py`
- Create: `src/hbv_multilead_joint_uncertainty/methods.py`
- Create: `src/hbv_multilead_joint_uncertainty/runner.py`

**Steps:**
1. Write failing tests for open loop, one fixed filter, parameter-only, noise-only, and joint banks with candidate counts
   one, one, three, three, and nine.
2. Verify all methods share origins, targets, forcing, observation history, initial state, and observation covariance.
3. Verify equal noise identifiers use exactly equal absolute process covariance and equal initial covariance across all
   parameter vectors; reject parameter-dependent rescaling.
4. Implement serial daily assimilation, copied open-loop forecast branches, and explicit full/grouped/no-interaction
   modes. Freeze the formal interaction mode from development-period evidence only.
5. Add one-candidate equality and future-discharge sentinel tests.
6. Run focused tests and the entire isolated suite.

### Task 5: Build immutable contract and result packages

**Files:**
- Create: `test/test_hbv_multilead_experiment.py`
- Create: `src/hbv_multilead_joint_uncertainty/experiment.py`
- Create: `src/hbv_multilead_joint_uncertainty/resource_monitor.py`
- Create: `src/hbv_multilead_joint_uncertainty/orchestrator.py`
- Create: `src/hbv_multilead_joint_uncertainty/scripts/run_multilead.py`

**Steps:**
1. Write failing tests for non-overwrite, two-stage contract consumption, atomic registry updates, exact array sets and
   shapes, metric recomputation, source/input snapshots, resource history, and coordinated-tamper rejection.
2. Implement `prepare-contract`, `run-contract`, and `verify-output` commands.
3. Save exact parameter vectors, all process and observation variances, input provenance, origin/target dates, method
   predictions, weights, state diagnostics, metrics, and cross-basin summaries.
4. Enforce the 25% start, 20% running-memory, 60% estimated-peak, two-processor, 50-GiB, three-times-output, and 30-second
   monitoring gates.
5. Run focused tests and independent artifact tamper tests.

### Task 6: Six-basin pilot and independent review loop

**Files:**
- Create only under: `results/23_hbv_multilead_joint_uncertainty/<pilot_contract_id>/`
- Create only under: `results/23_hbv_multilead_joint_uncertainty/<pilot_experiment_id>/`
- Create only under: `logs/23_hbv_multilead_joint_uncertainty/<pilot_experiment_id>/`

**Steps:**
1. Prepare and independently audit a six-basin contract without reading evaluation results.
2. Run a short smoke case, verify it in a separate process, then run all six basins for the frozen year.
3. Give an independent reviewer the goal, raw code/config/artifacts, but no implementer conclusion.
4. Reproduce every finding separately. Add a failing test and fix confirmed defects; record counter-evidence and make no
   code change for disproved findings.
5. Repeat until the latest reviewed experiment identifier has no confirmed unresolved defect.

### Task 7: Sixteen-basin formal preflight

**Files:**
- Create only under: `results/23_hbv_multilead_joint_uncertainty/<formal_contract_id>/`
- Create only under: `results/23_hbv_multilead_joint_uncertainty/<formal_experiment_id>/`
- Create only under: `logs/23_hbv_multilead_joint_uncertainty/<formal_experiment_id>/`

**Steps:**
1. Check resources, freeze the independently recomputed sixteen-basin contract, and record its checksum before any
   evaluation read.
2. Process one basin at a time with resource samples no more than 30 seconds apart.
3. Recompute all per-basin metrics and cross-basin summaries in a separate process.
4. Verify one-, three-, and seven-day arrays have 358 common origins and correct target dates.
5. Preserve failed or superseded runs with explicit registry status; never reuse an experiment identifier.

### Task 8: Final independent audit and bounded conclusion

**Files:**
- Create: `logs/23_hbv_multilead_joint_uncertainty/<formal_experiment_id>/code_review.md`
- Create: `logs/23_hbv_multilead_joint_uncertainty/<formal_experiment_id>/result_review.md`
- Create: `logs/23_hbv_multilead_joint_uncertainty/<formal_experiment_id>/finding_verification.md`
- Create: `logs/23_hbv_multilead_joint_uncertainty/<formal_experiment_id>/final_report.md`

**Steps:**
1. Run every new and inherited test fresh and verify the formal package fresh.
2. Audit every input, parameter, noise, interaction mode, chronology, basin-selection, resource, registry, and result requirement against a
   direct artifact or command.
3. Report each lead and basin, median change versus the fixed-filter baseline, strict wins, and the parameter/noise
   ablation attribution.
4. State explicitly that future observed meteorology makes this a diagnostic hindcast and prevents an operational
   forecast claim.
5. Issue a feasible or infeasible conclusion without requiring a positive result and without extrapolating to 531
   basins or writing a paper claim.
