# Highest-Posterior Candidate Forecast Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add and formally evaluate a forecast that uses the candidate with the highest final assimilation posterior, while sharing the exact no-state-interaction assimilation and candidate forecasts with posterior-weighted averaging.

**Architecture:** Extend the existing interaction-value comparison with an opt-in fifth method. Preserve the historical four-method default bit-for-bit; the new experiment enables the fifth method through a frozen config, saves its selected candidate and shared candidate forecasts, and reports a paired block-bootstrap comparison against posterior-weighted averaging.

**Tech Stack:** Python 3.11, NumPy, pytest, JSON, Git.

---

### Task 1: Specify highest-posterior selection with failing unit tests

**Files:**
- Modify: `test/test_hbv_interaction_value_comparison.py`
- Modify: `src/hbv_multilead_joint_uncertainty/interaction_value_comparison.py`

**Step 1: Write failing tests**

Add tests that require:

```python
selected_index, selected_forecast = highest_posterior_forecast(
    daily_probabilities,
    candidate_forecasts,
)
```

The tests must prove:

- selection uses only the final assimilation posterior;
- all lead times use the same selected candidate;
- an exact tie selects the lowest configured candidate index;
- invalid probability and candidate-forecast shapes are rejected;
- inputs are not mutated.

**Step 2: Run the focused tests and verify RED**

Run:

```powershell
$env:PYTHONIOENCODING='utf-8'
$env:PYTHONPATH='src'
python -m pytest -p no:cacheprovider test/test_hbv_interaction_value_comparison.py -q
```

Expected: failure because `highest_posterior_forecast` does not exist.

**Step 3: Implement the pure selection function**

Implement only validation, deterministic `numpy.argmax` selection on the final probability row, and extraction of `candidate_forecasts[:, selected_index]`.

**Step 4: Run the focused tests and verify GREEN**

Expected: all focused tests pass.

**Step 5: Commit**

```powershell
git add src/hbv_multilead_joint_uncertainty/interaction_value_comparison.py test/test_hbv_interaction_value_comparison.py
git commit -m "feat(id23): add highest-posterior forecast selection"
```

### Task 2: Share no-interaction assimilation and candidate forecasts

**Files:**
- Modify: `test/test_hbv_interaction_value_comparison.py`
- Modify: `src/hbv_multilead_joint_uncertainty/interaction_value_comparison.py`
- Modify: `src/hbv_multilead_joint_uncertainty/scripts/run_g3_phase2_interaction_value.py`

**Step 1: Write failing driver tests**

Require an opt-in argument:

```python
compare_interaction_arms(..., include_highest_posterior=True)
```

The tests must prove:

- the default method tuple remains exactly `("full", "none", "static", "oracle")`;
- the opt-in tuple adds `"highest_posterior"` without changing the four historical forecasts;
- the saved highest-posterior forecast equals the saved no-interaction candidate forecast at the saved selected index;
- the saved selected index equals `argmax` of the saved final no-interaction posterior;
- the no-interaction posterior-weighted forecast remains exactly the probability-weighted sum of those same candidate forecasts;
- evidence arrays conditionally include `forecast_none_candidates` and `highest_posterior_candidate_indices`.

**Step 2: Run the focused tests and verify RED**

Expected: failure because the opt-in argument and evidence arrays are absent.

**Step 3: Implement one-pass shared computation**

Refactor the no-interaction path internally so one assimilation and one forecast return:

- daily posterior probabilities;
- candidate forecasts;
- posterior-weighted combined forecast.

When enabled, derive the highest-posterior result from these arrays. Do not rerun assimilation and do not change the public return value of `assimilate_family_arm`.

**Step 4: Run focused and historical regression tests**

Run:

```powershell
$env:PYTHONIOENCODING='utf-8'
$env:PYTHONPATH='src'
python -m pytest -p no:cacheprovider test/test_hbv_interaction_value_comparison.py test/test_hbv_corrected_forecast_comparison.py test/test_hbv_forecast_frozen_transition.py -q
```

Expected: all tests pass; the old four-method packaged test remains unchanged.

**Step 5: Commit**

```powershell
git add src/hbv_multilead_joint_uncertainty/interaction_value_comparison.py src/hbv_multilead_joint_uncertainty/scripts/run_g3_phase2_interaction_value.py test/test_hbv_interaction_value_comparison.py
git commit -m "feat(id23): compare highest-posterior candidate forecast"
```

### Task 3: Add paired inference and packaged evidence

**Files:**
- Create: `test/test_hbv_highest_posterior_forecast.py`
- Modify: `src/hbv_multilead_joint_uncertainty/interaction_value_comparison.py`
- Modify: `src/hbv_multilead_joint_uncertainty/scripts/run_g3_corrected_forecast_comparison.py`

**Step 1: Write failing summary and package tests**

Require:

- `paired_highest_posterior_minus_none` with mean and ninety-five-percent interval;
- per-lead classifications `improves`, `harms`, or `no_detectable_difference`;
- selected candidate indices and shared candidate forecasts in `evidence.npz`;
- the new method in root-mean-square error and oracle-ratio summaries;
- no new fields or arrays when the historical config does not opt in;
- non-overwrite behavior and protected-file checks unchanged.

**Step 2: Run tests and verify RED**

Run:

```powershell
$env:PYTHONIOENCODING='utf-8'
$env:PYTHONPATH='src'
python -m pytest -p no:cacheprovider test/test_hbv_highest_posterior_forecast.py test/test_hbv_corrected_forecast_comparison.py -q
```

Expected: failure because the paired result and opt-in package are absent.

**Step 3: Implement conditional summary and packaging**

Use the existing paired block-bootstrap function and bootstrap seed. Keep historical output unchanged when the new method is disabled.

**Step 4: Run focused tests and verify GREEN**

Expected: all tests pass.

**Step 5: Commit**

```powershell
git add src/hbv_multilead_joint_uncertainty/interaction_value_comparison.py src/hbv_multilead_joint_uncertainty/scripts/run_g3_corrected_forecast_comparison.py test/test_hbv_highest_posterior_forecast.py
git commit -m "feat(id23): package highest-posterior forecast evidence"
```

### Task 4: Freeze the new formal experiment before execution

**Files:**
- Create: `src/hbv_multilead_joint_uncertainty/configs/g3_highest_posterior_forecast_param_switch_v01.json`
- Modify: `src/hbv_multilead_joint_uncertainty/configs/g3_experiment_registry.csv`
- Modify: `.gitattributes`

**Step 1: Create the new config**

Copy the corrected forecast config and change only:

- experiment identifier;
- design-document path and purpose;
- enabled comparison methods;
- bootstrap seed to `3308757`;
- highest-posterior decision rules and hypotheses;
- protected paths to include the corrected experiment and its config;
- new output path.

**Step 2: Add a preregistered registry row**

Use one stable experiment identifier, one config, and one result directory. Mark it `preregistered`; do not claim completion.

**Step 3: Protect sealed result bytes**

Add binary attributes for the new result directory and its external preregistration file before execution.

**Step 4: Run the complete pre-execution suite**

Run:

```powershell
$env:PYTHONIOENCODING='utf-8'
$env:PYTHONPATH='src'
python -m pytest -p no:cacheprovider test/test_hbv_highest_posterior_forecast.py test/test_hbv_corrected_forecast_comparison.py test/test_hbv_interaction_value_comparison.py test/test_hbv_three_stage_switching_validation.py test/test_hbv_forecast_frozen_transition.py test/test_hbv_forecast_weight_drift.py test/test_hbv_joint_uncertainty_imm.py test/test_hbv_multilead_forecast.py -q
```

Expected: all tests pass with only the existing unknown-pytest-option warning.

**Step 5: Commit before any formal result generation**

```powershell
git add .gitattributes docs/plans/2026-07-26-g3-highest-posterior-forecast.md src/hbv_multilead_joint_uncertainty/configs/g3_highest_posterior_forecast_param_switch_v01.json src/hbv_multilead_joint_uncertainty/configs/g3_experiment_registry.csv
git commit -m "phase(id23): preregister highest-posterior forecast comparison"
```

### Task 5: Run and independently verify the new experiment

**Files:**
- Create only: `results/23_hbv_multilead_joint_uncertainty/g3_highest_posterior_forecast_param_switch_v01/`
- Create only: `results/23_hbv_multilead_joint_uncertainty/g3_highest_posterior_forecast_param_switch_v01.preregistered.json`

**Step 1: Confirm resources and protected hashes**

Run the existing resource preflight and record the protected-path hashes through the runner. Do not start if any required input hash differs.

**Step 2: Execute once**

Run:

```powershell
$env:PYTHONIOENCODING='utf-8'
$env:PYTHONPATH='src'
python -m hbv_multilead_joint_uncertainty.scripts.run_g3_corrected_forecast_comparison `
  --repo-root . `
  --config src/hbv_multilead_joint_uncertainty/configs/g3_highest_posterior_forecast_param_switch_v01.json `
  --output-dir results/23_hbv_multilead_joint_uncertainty/g3_highest_posterior_forecast_param_switch_v01
```

Expected: one successful non-overwriting result package.

**Step 3: Independently recompute raw evidence**

From `evidence.npz`, independently recompute:

- selected indices from final no-interaction posterior;
- selected forecasts from candidate forecasts;
- posterior-weighted forecasts;
- all five methods' root-mean-square errors;
- paired block differences and intervals;
- per-lead classifications;
- checksums and protected-file identity.

**Step 4: Perform independent method and code review**

The reviewer must verify that the new comparison changes only the final forecast combination rule and does not read future flow or truth.

**Step 5: Resolve confirmed findings only**

For any defect, add a failing regression test before the fix. Do not rerun or overwrite the sealed experiment; use a new experiment identifier if a result-affecting defect exists.

### Task 6: Close, verify, and integrate

**Files:**
- Create: `docs/plans/2026-07-26-g3-highest-posterior-forecast-closure.md`
- Modify: `src/hbv_multilead_joint_uncertainty/configs/g3_experiment_registry.csv`
- Add only the new sealed result files.

**Step 1: Write the bounded closure**

Report the five methods, exact one-day, three-day, and seven-day numbers, paired intervals, interpretation, scope limit, and independent review outcome. End with a concrete conclusion.

**Step 2: Mark the registry row completed only if released**

If any blocking finding remains, keep the status non-complete.

**Step 3: Run fresh verification**

Run the full pre-execution suite again, verify every new checksum from raw bytes, and confirm all old protected hashes are unchanged.

**Step 4: Commit scoped files**

Stage only the new design, plan, code, tests, config, registry row, closure, preregistration, and result package.

**Step 5: Merge into `migration/reorg-v1`**

Merge only after tests, raw-evidence recomputation, and both independent reviews pass. Preserve all unrelated dirty-worktree changes.
