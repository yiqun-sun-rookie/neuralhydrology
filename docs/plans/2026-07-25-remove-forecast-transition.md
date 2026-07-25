# Remove Forecast-Phase Model Switching Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make every short-range forecast freeze candidate probabilities and remove the forecast-phase model-switching option from all current experiment APIs.

**Architecture:** Assimilation keeps the existing model-switching transition matrix. `forecast_from_posterior()` deep-copies the posterior bank, replaces only the copy's transition matrix with identity, and then uses the existing forecast loop. All downstream forwarding parameters and validation branches are deleted.

**Tech Stack:** Python, NumPy, pytest.

---

### Task 1: Replace dual-mode tests with the single forecast contract

**Files:**
- Modify: `test/test_hbv_forecast_frozen_transition.py`

**Step 1: Write the failing tests**

- Change the default forecast assertion to require constant probabilities.
- Require default full interaction and no interaction to produce identical forecast paths.
- Assert `forecast_transition` is absent from the core and downstream function signatures.
- Assert passing the removed keyword raises `TypeError`.
- Keep the input-bank immutability assertion.

**Step 2: Run the focused file and verify failure**

Run:
`$env:PYTHONIOENCODING='utf-8'; $env:PYTHONPATH='src'; python -m pytest test/test_hbv_forecast_frozen_transition.py -q`

Expected: failures showing that the current default still drifts and the obsolete keyword is still accepted.

### Task 2: Make the core forecast always freeze

**Files:**
- Modify: `src/hbv_multilead_joint_uncertainty/forecast.py`

**Step 1: Implement the minimum change**

- Remove the `forecast_transition` parameter and validation.
- After deep-copying the posterior bank, always set the copied estimator's transition matrix to identity.
- Update the docstring to state the single forecast contract.

**Step 2: Run the focused core tests**

Run:
`$env:PYTHONIOENCODING='utf-8'; $env:PYTHONPATH='src'; python -m pytest test/test_hbv_forecast_frozen_transition.py -q`

Expected: core behavior tests pass; downstream signature tests still fail until Task 3.

### Task 3: Remove downstream forwarding APIs

**Files:**
- Modify: `src/hbv_multilead_joint_uncertainty/three_stage_switching_validation.py`
- Modify: `src/hbv_multilead_joint_uncertainty/interaction_value_comparison.py`

**Step 1: Remove obsolete parameters**

- Delete `forecast_transition` from all function signatures.
- Delete forwarding keyword arguments and mode validation.
- Rewrite docstrings to describe permanently frozen forecast probabilities.

**Step 2: Run the focused tests**

Run:
`$env:PYTHONIOENCODING='utf-8'; $env:PYTHONPATH='src'; python -m pytest test/test_hbv_forecast_frozen_transition.py -q`

Expected: all focused tests pass.

### Task 4: Update current documentation

**Files:**
- Modify: `docs/plans/2026-07-25-forecast-frozen-transition.md`
- Modify: `src/hbv_multilead_joint_uncertainty/HANDOFF_20260725_frozen_transition.md`

**Step 1: Mark the former dual-mode design as superseded**

- State that current forecasts always freeze.
- Remove instructions telling future experiments to opt into `"frozen"`.
- Preserve historical test numbers and the old commit as historical evidence.

**Step 2: Prove obsolete configuration text is gone**

Run:
`rg -n --hidden -g '!results/**' -g '!logs/**' -g '!.git/**' "forecast_transition|forecast_transition=.markov.|forecast_transition=.frozen." src/hbv_multilead_joint_uncertainty test docs/plans`

Expected: no live code, test, plan, or handoff matches.

### Task 5: Run regression verification

**Files:**
- Verify only; do not modify sealed results.

**Step 1: Run the related regression set**

Run:
`$env:PYTHONIOENCODING='utf-8'; $env:PYTHONPATH='src'; python -m pytest test/test_hbv_forecast_frozen_transition.py test/test_hbv_multilead_forecast.py test/test_hbv_three_stage_switching_validation.py test/test_hbv_interaction_value_comparison.py test/test_hbv_forecast_weight_drift.py test/test_hbv_joint_uncertainty_imm.py -q`

Expected: all collected tests pass with zero failures.

**Step 2: Inspect the final scope**

Run:
`git diff --check`

Run:
`git status --short -- src/hbv_multilead_joint_uncertainty test/test_hbv_forecast_frozen_transition.py docs/plans/2026-07-25-forecast-frozen-transition.md docs/plans/2026-07-25-remove-forecast-transition.md`

Expected: only the planned files are changed; unrelated dirty-worktree files remain untouched.

### Task 6: Commit the implementation

**Step 1: Stage only the planned files**

Use explicit `git add -- <file list>`; never use `git add .`.

**Step 2: Review the staged diff**

Run:
`git diff --cached --check`

Run:
`git diff --cached --stat`

**Step 3: Commit**

Run:
`git commit -m "fix(id23): remove forecast-phase model switching"`
