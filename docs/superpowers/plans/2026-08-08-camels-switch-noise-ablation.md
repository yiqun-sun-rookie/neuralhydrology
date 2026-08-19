# CAMELS-US Parameter-Switch Noise Ablation Implementation Plan

> **For Codex:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Test whether aligning the filter-assumed process-noise structure with the synthetic truth, or reducing its variance, improves parameter-switch identification without making the synthetic observations or truth easier.

**Architecture:** Keep the existing 531-basin synthetic truth generator, observation generator, three-candidate parameter bank, switch schedule, scoring rule, and design seeds 0 and 1 fixed. Add one explicit filter process-covariance structure selector, then compare two isolated exploratory treatments against the completed baseline: lower-groundwater-only covariance at variance scale `1e-7`, and all-five-hydrologic-state covariance at variance scale `1e-8`. Write every treatment to a unique result directory and retain the existing baseline unchanged.

**Tech Stack:** Python, NumPy, pandas, pytest, existing CAMELS-US switching confirmation runner.

---

### Task 1: Register the exploratory treatments and invariants

**Files:**
- Create: `docs/superpowers/plans/2026-08-08-camels-switch-noise-ablation.md`

**Step 1: Record the reused baseline**

- Baseline label: `design531_widebank_q1e7_s01_20260808_local`
- Baseline filter covariance: all five hydrologic states, variance scale `1e-7`
- Baseline synthetic truth noise: lower-groundwater state lognormal standard deviation `0.02`
- Baseline synthetic observation noise: unchanged basin-specific `sigma_obs`
- Baseline scope: exploratory design evidence only because seeds 0 and 1 were used in design.

**Step 2: Register the two isolated treatments**

| Experiment | Filter covariance structure | Variance scale | Truth noise | Generated observation noise | Output label |
|---|---:|---:|---:|---:|---|
| N01 | lower-groundwater state only | `1e-7` | unchanged | unchanged | `noise_n01_slzonly_q1e7_s01_20260808_local` |
| N02 | all five hydrologic states | `1e-8` | unchanged | unchanged | `noise_n02_all5_q1e8_s01_20260808_local` |
| N03 | lower-groundwater state only | `1e-8` | unchanged | unchanged | `noise_n03_slzonly_q1e8_s01_20260808_local` |

N01 changes only the filter-assumed covariance structure. N02 changes only the filter-assumed covariance magnitude. Neither treatment changes the data-generating truth or observations.
N03 is a follow-up combination and is run only if N01 and N02 both pass the
screen; it must not be interpreted as a single-factor effect.

### Task 2: Add the filter covariance structure selector

**Files:**
- Modify: `src/camels_switch_confirmation/g2_switch_confirmation.py`
- Test: `test/test_camels_switch_confirmation.py`

**Step 1: Write failing unit tests**

Test that the default structure is numerically identical to the existing process covariance, that lower-groundwater-only structure has exactly one nonzero diagonal entry at the lower-groundwater state, and that an unknown structure is rejected.

**Step 2: Implement the smallest selector**

Add `build_filter_process_covariance()` and a command-line option. Preserve the existing behavior as the default and record the selected structure in the summary and probability files.

**Step 3: Run focused tests**

Run: `python -m pytest -q test/test_camels_switch_confirmation.py`

Expected: all tests pass.

### Task 3: Smoke-test both treatments

**Files:**
- Read: `src/camels_switch_confirmation/g2_switch_confirmation.py`
- Create: unique result directories under `results/23_camels_switch_confirmation/`

**Step 1: Verify output labels are unused**

Abort rather than overwrite if either result directory already contains files.

**Step 2: Run one-basin smoke tests with separate smoke labels**

Run each treatment with `--limit 1 --workers 1` and verify two successful tasks, finite normalized probabilities, six events per task, and zero truth-state clips.

### Task 4: Run the 531-basin exploratory treatments sequentially

**Files:**
- Create: `results/23_camels_switch_confirmation/g2_switch_confirmation_v01_noise_n01_slzonly_q1e7_s01_20260808_local/`
- Create: `results/23_camels_switch_confirmation/g2_switch_confirmation_v01_noise_n02_all5_q1e8_s01_20260808_local/`
- Create: separate standard-output and standard-error logs under `tmp/`

**Step 1: Screen both single-factor treatments on the first 50 registered basins**

The first 50 table rows are selected before inspecting treatment outcomes. Run
both treatments sequentially with two workers and compare them with the same
50 basins from the completed baseline.

**Step 2: Screen the combination only when both single factors improve**

Run N03 on the same 50 basins only after both N01 and N02 satisfy the screening
criterion.

**Step 3: Promote only a treatment that improves the registered baseline**

Require a higher overall event pass rate without a lower center-target event
pass rate. If both treatments fail that screen, stop without a new 531-basin
run. If either passes, run the better treatment on 531 basins times 2 seeds =
1062 tasks. Never overlap runs.

### Task 5: Independently verify and compare

**Files:**
- Read: each `g2_summary.json`, `g2_events.csv`, `g2_basin_verdicts.csv`, and all probability files.

**Step 1: Integrity checks**

For each treatment verify 1062 successful tasks, zero failures, 6372 event rows after wide conversion, zero truth clips, 1062 probability files, finite values, and posterior rows summing to one.

**Step 2: Identification comparison**

Compare overall, center-target, extreme-target, six directed transitions, rainfall thirds within direction, and seed agreement against the completed baseline. Report paired basin/event changes, not only aggregate percentages.

**Step 3: Enforce claim boundaries**

Label every result exploratory and design-set-only. Do not claim complete-state accuracy, forecast value, real-observation assimilation value, or validation. Untouched seeds 2 and 3 remain reserved for the post-freeze validation run.

### Task 6: Search filter-noise settings without making the data easier

**Files:**
- Registry: `docs/plans/2026-08-08-camels-noise-search-registry-v01.csv`
- Queue: `tmp/run_camels_noise_qgrid_after_n03.ps1`

**Fixed data-generating factors:** synthetic truth lognormal noise standard
deviation `0.02`, generated observation series, candidate bank, forcing,
switch schedule, and event rule. Never select a setting by reducing the actual
truth or generated-observation noise.

**Stage 1:** With filter process covariance restricted to the lower-groundwater
state, compare the seven-point variance-scale grid `1e-6`, `3e-7`, `1e-7`,
`3e-8`, `1e-8`, `3e-9`, and `1e-9`. Reuse existing `1e-7` and `1e-8`
outputs and run the other five sequentially on the same first 50 basins.

**Selection rule:** Require overall event pass rate at least `61.83%` (no more
than two percentage points below N03). Among eligible settings, maximize the
minimum of the six directed-transition pass rates. Break ties by lower
post-burn-in multiclass Brier score for the daily true candidate, then by
higher overall event pass rate. Also report the true-candidate negative log
probability; it is diagnostic and cannot override the registered rule.

**Stage 2:** After Stage 1, compare a lower-groundwater process variance
proportional to the current lower-groundwater state squared with multipliers
`0.25`, `1`, and `4` around the variance implied by the truth's lognormal
noise. This requires implementation only after the active NS00 run ends.

**Stage 3:** Treat filter observation-covariance multipliers `0.5` and `2` as
sensitivity checks with the generated observations unchanged. A deliberately
mis-specified observation covariance is not eligible as the primary setting
solely because it raises the identification pass rate.
