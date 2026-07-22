# Daily HBV Joint-Uncertainty Prototype Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build and independently verify a registered six-basin daily HBV-lite interacting multiple-model prototype whose
candidate bank varies both complete parameter vectors and process-noise levels.

**Architecture:** Add an isolated `src/hbv_joint_uncertainty` workspace that wraps the authoritative NumPy HBV-lite
equations in an exact Markov state adapter, implements a local modified unscented Kalman filter and parameter-conditioned
state interaction, and runs only a frozen six-basin preflight. Existing trained parameter tables and both source
repositories remain read-only.

**Tech Stack:** Python 3.11, NumPy, SciPy, pandas, pytest, Windows resource counters, optional `nvidia-smi`.

---

The user has not authorized version-control commits. Every commit step normally required by this plan is replaced by a
fresh test command, a diff inspection, and a recorded checkpoint. Do not stage, commit, push, or create a worktree.

### Task 1: Prove the exact state contract

**Files:**
- Create: `test/test_hbv_joint_uncertainty_state_dimension.py`
- Create: `src/hbv_joint_uncertainty/__init__.py`
- Create: `src/hbv_joint_uncertainty/hbv_adapter.py`

**Steps:**
1. Write a failing test showing two ten-day routing histories with the same five stores and newest nine runoff values but
   different oldest runoff values produce different observations.
2. Run `pytest test/test_hbv_joint_uncertainty_state_dimension.py -v` and confirm failure because the adapter is absent.
3. Implement only state names, packing validation, and the ten-value routing observation.
4. Run the test and confirm it passes.
5. Inspect `git diff -- test/test_hbv_joint_uncertainty_state_dimension.py src/hbv_joint_uncertainty`.

### Task 2: Implement and verify the exact daily adapter

**Files:**
- Modify: `src/hbv_joint_uncertainty/hbv_adapter.py`
- Create: `test/test_hbv_joint_uncertainty_adapter.py`

**Steps:**
1. Write failing one-day and sequential tests for default initialization, each of the five stores, raw runoff, routing
   queue order, `lag_time = 1`, and `lag_time = 10`.
2. Confirm failure with `pytest test/test_hbv_joint_uncertainty_adapter.py -v`.
3. Implement one daily transition directly from `src/scl_hydro/hbv_lite_numpy.py`, preserving operation order and
   `float64` arithmetic.
4. Add warm-up replay that returns the five stores and ten raw-runoff values.
5. Compare 365 deterministic days against `simulate_hbv_lite`; require maximum absolute error at most `1e-8`.
6. Run the two state/adapter test files together and inspect the diff.

### Task 3: Implement the standalone modified unscented Kalman filter

**Files:**
- Create: `src/hbv_joint_uncertainty/sigma_filter.py`
- Create: `test/test_hbv_joint_uncertainty_sigma_filter.py`

**Steps:**
1. Write failing tests for `2n+1` sigma points, symmetric covariance, process-noise inclusion before regenerated
   measurement sigma points, finite log likelihood, and deterministic linear-system agreement.
2. Confirm expected failures.
3. Implement the minimum scaled sigma-point, predict, and update operations, retaining the hourly reference parameters
   `alpha = 0.6874`, `beta = 2`, and `kappa = -2`.
4. Add bounded diagonal jitter escalation and explicit errors for irrecoverable covariance matrices.
5. Run the focused test file and inspect the diff.

### Task 4: Implement parameter-conditioned interacting multiple-model estimation

**Files:**
- Create: `src/hbv_joint_uncertainty/imm.py`
- Create: `test/test_hbv_joint_uncertainty_imm.py`

**Steps:**
1. Write failing tests for full-bank probability prediction, within-parameter state mixing, prohibited cross-parameter
   state mixing, stable log-likelihood normalization, and exact one-candidate reduction.
2. Confirm expected failures.
3. Implement interaction, filtering, posterior probability update, and combined state/covariance.
4. Require probability error at most `1e-12` and fail on non-finite candidate outputs.
5. Run all four focused test files and inspect the diff.

### Task 5: Freeze candidate, basin, resource, and artifact contracts

**Files:**
- Create: `src/hbv_joint_uncertainty/candidates.py`
- Create: `src/hbv_joint_uncertainty/resource_monitor.py`
- Create: `src/hbv_joint_uncertainty/configs/preflight_v01.json`
- Create: `src/hbv_joint_uncertainty/configs/preflight_v01_basins.csv`
- Create: `test/test_hbv_joint_uncertainty_contracts.py`

**Steps:**
1. Write failing tests for one checksum-locked trained source, three deterministic parameter vectors, three noise levels,
   nine unique candidates, six unique basins, source
   checksums, output non-overwrite, and each resource threshold.
2. Confirm expected failures.
3. Implement read-only parameter loading and resource snapshots. Reject missing rows, failed source runs, inconsistent
   metadata, parameter values outside frozen bounds, and duplicate candidates.
4. Freeze one experiment family and its six-basin list before execution.
5. Run the contract tests and inspect the frozen files.

### Task 6: Build the registered preflight runner

**Files:**
- Create: `src/hbv_joint_uncertainty/preflight.py`
- Create: `src/hbv_joint_uncertainty/scripts/__init__.py`
- Create: `src/hbv_joint_uncertainty/scripts/run_preflight.py`
- Create: `test/test_hbv_joint_uncertainty_preflight.py`

**Steps:**
1. Write failing tests with short deterministic forcing for warm-up provenance checks, atomic artifact writing, registry
   rows, checksums, resume refusal, resource samples, and saved probability normalization.
2. Confirm expected failures.
3. Implement the minimum runner and command-line interface. Output prior discharge before observing the same day's flow;
   do not label posterior assimilation fit as forecast skill.
4. Run the focused test and then all `test/test_hbv_joint_uncertainty_*.py` files.
5. Run a dry resource estimate and one-basin, 30-day smoke experiment in a new experiment directory.

### Task 7: Run the frozen six-basin preflight

**Files:**
- Create only under: `results/22_hbv_joint_uncertainty/<experiment_id>/`
- Create only under: `logs/22_hbv_joint_uncertainty/<experiment_id>/`

**Steps:**
1. Capture a resource snapshot and verify the memory and disk gates.
2. Run one basin at a time over the frozen 365-day interval.
3. Monitor resources at most 60 seconds apart while the command is active.
4. Verify the output directory contains the frozen configuration, registry row, metrics, state diagnostics, probability
   histories, resource history, log, and checksums.
5. Recompute all reported diagnostics from saved files in a separate process.

### Task 8: Independent audit, finding verification, and final audit

**Files:**
- Create: `logs/22_hbv_joint_uncertainty/<experiment_id>/code_review.md`
- Create: `logs/22_hbv_joint_uncertainty/<experiment_id>/result_review.md`
- Create: `logs/22_hbv_joint_uncertainty/<experiment_id>/finding_verification.md`
- Create: `logs/22_hbv_joint_uncertainty/<experiment_id>/final_report.md`

The audit records live beside, rather than inside, the result package. The result package is immutable after its verifier
has committed the checksums and registry row; adding review documents there would invalidate that contract.

**Steps:**
1. Give an independent reviewer only the goal, source diff, frozen configuration, and raw artifacts; withhold implementer
   conclusions.
2. For every finding, add a separate reproducer or rerun. Fix confirmed findings through a new failing test and repeat
   the relevant implementation task. Record disproved findings with the counter-evidence and make no code change.
3. Run `pytest test/test_hbv_joint_uncertainty_*.py -v` fresh.
4. Re-run the saved-artifact verifier fresh.
5. Audit every completion criterion against direct file or command evidence and issue only an engineering-feasibility
   conclusion, not a 531-basin or paper-performance claim.
