# Corrected Multi-Day Forecast Comparison Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Run and seal a corrected 1-, 3-, and 7-day comparison in which model switching and candidate-state mixing are absent during forecasting.

**Architecture:** Add a new runner beside the frozen historical runner. It deterministically replays the existing three-stage update, aborts unless all truth and update-period arrays exactly match sealed evidence, then reuses the current four-method comparison under the corrected forecast contract and writes a new atomic evidence package.

**Tech Stack:** Python, NumPy, pytest, JSON, Git.

---

### Task 1: Freeze the experiment contract

**Files:**
- Create: `docs/plans/2026-07-25-g3-corrected-forecast-comparison-design.md`
- Create: `src/hbv_multilead_joint_uncertainty/configs/g3_corrected_forecast_param_switch_v01.json`
- Create: `src/hbv_multilead_joint_uncertainty/configs/g3_experiment_registry.csv`

**Step 1:** Record the one-factor change, exact integrity gate, output path, and decision rule.

**Step 2:** Commit the design, configuration, and registry before running scientific computation.

### Task 2: Add the replay-integrity gate

**Files:**
- Create: `test/test_hbv_corrected_forecast_comparison.py`
- Create: `src/hbv_multilead_joint_uncertainty/scripts/run_g3_corrected_forecast_comparison.py`

**Step 1: Write the failing tests**

Test that the gate accepts exact truth and update-period arrays while allowing forecast arrays to differ, and rejects any update-period mismatch.

**Step 2: Run tests to verify failure**

Run:

`$env:PYTHONIOENCODING='utf-8'; $env:PYTHONPATH='src'; python -m pytest test/test_hbv_corrected_forecast_comparison.py -q`

Expected: failure because the new runner does not exist.

**Step 3: Write the minimal implementation**

Implement exact comparison for forcing, truth, observations, update probabilities, update states, and origin states. Exclude only forecast-derived method arrays.

**Step 4: Run tests to verify success**

Run the same command and require zero failures.

### Task 3: Add atomic packaging and result classification

**Files:**
- Modify: `test/test_hbv_corrected_forecast_comparison.py`
- Modify: `src/hbv_multilead_joint_uncertainty/scripts/run_g3_corrected_forecast_comparison.py`

**Step 1: Write the failing tests**

Test immutable output naming, non-overwrite behavior, corrected forecast metadata, and per-lead comparison labels derived from the frozen confidence-interval rule.

**Step 2: Run tests to verify failure**

Run the focused test file and confirm the expected failure.

**Step 3: Write the minimal implementation**

Write preregistration, config snapshot, raw arrays, summary, protected-file hashes, source snapshot, and checksums to an incomplete directory; publish by atomic rename only after all gates pass.

**Step 4: Run focused and regression tests**

Run:

`$env:PYTHONIOENCODING='utf-8'; $env:PYTHONPATH='src'; python -m pytest test/test_hbv_corrected_forecast_comparison.py test/test_hbv_interaction_value_comparison.py test/test_hbv_three_stage_switching_validation.py test/test_hbv_forecast_frozen_transition.py -q`

Expected: zero failures.

**Step 5: Commit**

Commit code and tests before the formal experiment starts.

### Task 4: Run and independently verify the formal comparison

**Files:**
- Create: `results/23_hbv_multilead_joint_uncertainty/g3_corrected_forecast_param_switch_v01/`
- Create: `docs/plans/2026-07-25-g3-corrected-forecast-comparison-closure.md`

**Step 1:** Verify the formal output path does not exist and run the committed configuration.

**Step 2:** Independently load `evidence.npz`, recompute all four root mean square errors, paired differences, confidence intervals, and labels without trusting `summary.json`.

**Step 3:** Confirm checksums and protected-file hashes.

**Step 4:** Write the closure using only independently verified numbers.

**Step 5:** Run the full focused regression suite and commit the evidence and closure.
