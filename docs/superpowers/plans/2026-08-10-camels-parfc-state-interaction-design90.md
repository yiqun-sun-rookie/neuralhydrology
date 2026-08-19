# CAMELS-US parFC State-Interaction Design90 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run one registered 90-basin, design-seed-only paired scale-up that tests whether full state interaction plus conservative soil-capacity state treatment continues to outperform the historical grouped-state method.

**Architecture:** Reuse the registered three-arm runner without changing the hydrologic model or filter. First generalize only the independent verifier's sample-size checks from hard-coded Design12 counts to configuration-derived counts, protected by exact regression and variable-size integration tests. Then mechanically select 90 basins without using prior switch outcomes, register every input and implementation hash, run all 540 tasks in a new output root, and independently recompute all 3,240 event decisions and probability scores.

**Tech Stack:** Python 3.11, NumPy, pandas, pytest, SHA-256, existing HBV-lite modified unscented Kalman filters and interacting multiple-model runner.

## Global Constraints

- The only writable code host is `G:\wt\camels-rising` on branch `codex/camels-rising-half-recal`.
- Preserve every pre-existing modification, untracked file, result directory, and log; do not clean or overwrite anything.
- Do not commit, push, modify the main repository, use seeds 2 or 3, create a validation-frozen version 02 configuration, or run all 531 basins.
- The experiment is exploratory and uses only design seeds 0 and 1.
- Arms A, B, and C must share truth, observations, forcing, candidate parameters, process noise, observation noise, stage schedule, transition matrix, and event rule exactly.
- A first task failure stops new submissions; already-running tasks may finish and must be recorded.
- The accepted conversational proposal of 15 basins per each of six strata is infeasible because the high-`r_min`, no-initial-overflow stratum contains only 9 basins. The registered correction must use the deterministic maximum-balanced allocation `16,16,16,16,9,17`, totaling 90 unique basins without replacement.
- The existing season-confounded seven-stage schedule is retained so Design90 is a scale replication of Design12. This experiment cannot separate direction from season and cannot by itself authorize validation.
- No task includes a Git commit because commit authorization was not granted.

---

### Task 1: Make the independent verifier sample-size aware

**Files:**
- Modify: `src/camels_switch_confirmation/verify_parameter_interaction_design.py`
- Modify: `test/test_camels_parameter_interaction_verifier.py`

**Interfaces:**
- Consumes: the registered basin list, seeds, three arms, and seven-stage rotation.
- Produces: expected total tasks, per-arm tasks, total events, per-arm events, and per-direction events derived from configuration rather than fixed `12/24/72/144/432` constants.

- [ ] **Step 1: Add a pure expected-count helper test for 90 basins**

```python
def test_expected_design_counts_for_90_basins():
    counts = expected_design_counts(
        basin_count=90, seed_count=2, arm_count=3, events_per_task=6
    )
    assert counts.total_tasks == 540
    assert counts.tasks_per_arm == 180
    assert counts.total_events == 3240
    assert counts.events_per_arm == 1080
    assert counts.events_per_direction_per_arm == 180
```

- [ ] **Step 2: Run the new test and record the expected import failure**

Run:

```powershell
$env:PYTHONPATH=(Resolve-Path 'src').Path
& 'C:\Users\yiqun\anaconda3\python.exe' -m pytest -q `
  test\test_camels_parameter_interaction_verifier.py::test_expected_design_counts_for_90_basins
```

Expected before implementation: failure because `expected_design_counts` does not exist.

- [ ] **Step 3: Implement the immutable count contract**

```python
@dataclass(frozen=True)
class ExpectedDesignCounts:
    basin_count: int
    seed_count: int
    arm_count: int
    events_per_task: int
    tasks_per_arm: int
    total_tasks: int
    events_per_arm: int
    total_events: int
    events_per_direction_per_arm: int


def expected_design_counts(*, basin_count, seed_count, arm_count, events_per_task):
    tasks_per_arm = basin_count * seed_count
    return ExpectedDesignCounts(
        basin_count=basin_count,
        seed_count=seed_count,
        arm_count=arm_count,
        events_per_task=events_per_task,
        tasks_per_arm=tasks_per_arm,
        total_tasks=tasks_per_arm * arm_count,
        events_per_arm=tasks_per_arm * events_per_task,
        total_events=tasks_per_arm * arm_count * events_per_task,
        events_per_direction_per_arm=tasks_per_arm,
    )
```

The helper must reject non-positive counts. `verify_design` must additionally require `design_selection.basin_count` to equal the unique basin-list length, seeds to equal `[0,1]`, exactly three registered arms, and exactly six distinct one-occurrence directions in the registered rotation.

- [ ] **Step 4: Replace every hard-coded Design12 count with the derived values**

Use the count object for root-summary tasks, arm summaries, runner rows, legacy-reference rows, final task and event tables, per-arm counts, and per-direction counts. Keep probability shapes, event formulas, hashes, cross-arm contracts, and Design12 metrics unchanged.

- [ ] **Step 5: Add a complete variable-size integration fixture**

Extend `_build_complete_design` with `basin_count`, populate `design_selection.basin_count`, and derive all synthetic runner counts. Add a two-basin end-to-end verifier test expecting 12 tasks and 72 events; retain the existing 12-basin test expecting 72 and 432.

- [ ] **Step 6: Run verifier and related regression tests**

Expected: every verifier test passes and the complete existing related suite remains green.

---

### Task 2: Register the deterministic 90-basin scale-up

**Files:**
- Create: `src/camels_switch_confirmation/register_parameter_interaction_design90.py`
- Create: `test/test_camels_parameter_interaction_design90_registration.py`
- Create: `docs/plans/2026-08-10-camels-parfc-state-interaction-design90-prereg-v01.md`
- Create mechanically: `docs/plans/2026-08-10-camels-parfc-state-interaction-design90-basins-v01.csv`
- Create mechanically: `docs/plans/2026-08-10-camels-parfc-state-interaction-design90-coverage-v01.csv`
- Create mechanically: `docs/plans/2026-08-10-camels-parfc-state-interaction-design90-input-manifest-v01.csv`
- Create mechanically: `docs/plans/2026-08-10-camels-parfc-state-interaction-design90-legacy-reference-v01.csv`
- Create: `docs/plans/2026-08-10-camels-parfc-state-interaction-design90-registry-v01.csv`
- Create mechanically: `docs/plans/2026-08-10-camels-parfc-state-interaction-design90-run-manifest-v01.json`
- Create mechanically: `src/camels_switch_confirmation/configs/camels_parfc_state_interaction_design90_01b.json`

**Interfaces:**
- Consumes: the 531-row first-stage precheck table, 531-row calibrated parameter table, exact raw CAMELS-US forcing and streamflow files, the old 531-basin Arm-A probability directory, and final implementation hashes.
- Produces: experiment `CAMELS_PARFC_STATE_INTERACTION_01B_DESIGN90` with one immutable exploratory config and output root `results/23_camels_switch_confirmation/camels_parfc_state_interaction_01b_design90_s01_20260810_local`.

- [ ] **Step 1: Test the mechanical selection independently of outcome columns**

The selector must sort 531 successful rows by `(r_min, basin_id)`, split exact ranks `0:177`, `177:354`, `354:531`, merge `state_SM`, classify `state_SM > fc_member2`, and allocate the six ordered cells as `16,16,16,16,9,17`. The size-9 cell must select every row. Other cells select interior ranks `round(k*(n-1)/(m+1))` for `k=1..m`, require unique indices, and never read event-pass or probability-result files.

- [ ] **Step 2: Test refusal of duplicate basins, existing artifacts, missing raw inputs, missing legacy references, non-finite forcing, and non-1260-day coverage**

Every output must use exclusive creation. Any failed registration leaves no configuration claiming a runnable registered experiment.

- [ ] **Step 3: Write the preregistration before generating the configuration**

Fix the same three arms and scientific settings as Design12. Register 540 tasks and 3,240 events. Record the corrected allocation, season-confounding limitation, design-only seed boundary, and that Design12 results informed the decision to scale but not basin selection.

- [ ] **Step 4: Generate and hash exact inputs**

The basin table records cell, source cell size, allocated size, within-cell rank, `r_min`, `state_SM`, bounded half-capacity, clipping flag, and predicted-identifiable flag. The coverage table requires 1,260 finite days from `1989-10-01` through `1993-03-13`. The raw manifest contains 184 rows: two files for each basin plus topography, loader source, parameter table, and precheck table. The legacy manifest contains exactly 180 Arm-A probability references from the completed old 531-basin design run.

- [ ] **Step 5: Register the decision gates**

The scale-up gate requires all 540 tasks and independent checks, C strictly more passed events than A, C no larger Brier score than A, and C no larger true-candidate negative log probability than A. Separately register the absolute eligibility gate before the run: C overall event pass rate at least `0.65`, C minimum direction pass rate at least `0.50`, C Brier score at most `2/3`, C stable true-candidate negative log probability at most `log(3)`, and the scale-up gate passed. Report task-pair signs and the fraction of exact-zero ordinary true probabilities. Passing the eligibility gate permits only a later user review; validation freeze and reserved-seed execution remain HOLD.

- [ ] **Step 6: Compute final hashes and run input integrity preflight without creating the output root**

Require 90 basins, 184 raw-manifest rows, 180 legacy references, every implementation hash matching, and the registered output root absent.

---

### Task 3: Run the isolated exploratory batch

**Files:**
- Consume: `src/camels_switch_confirmation/configs/camels_parfc_state_interaction_design90_01b.json`
- Create at runtime: `results/23_camels_switch_confirmation/camels_parfc_state_interaction_01b_design90_s01_20260810_local/`
- Create at runtime: `tmp/camels_parfc_state_interaction_01b_design90_s01_20260810_local.stdout.log`
- Create at runtime: `tmp/camels_parfc_state_interaction_01b_design90_s01_20260810_local.stderr.log`

**Interfaces:**
- Consumes: exact config path, exact config SHA-256, and four workers.
- Produces: three complete arm directories with 180 task probability files each, or a nonzero fail-fast record preserving all completed and unsubmitted work.

- [ ] **Step 1: Run syntax checks, all related tests, input hashes, output-absence check, and residual-process check**

- [ ] **Step 2: Start the registered runner once with four workers and redirected standard output and error**

```powershell
$env:PYTHONPATH=(Resolve-Path 'src').Path
& 'C:\Users\yiqun\anaconda3\python.exe' -X utf8 `
  -m camels_switch_confirmation.registered_parameter_interaction `
  --config src/camels_switch_confirmation/configs/camels_parfc_state_interaction_design90_01b.json `
  --config-sha256 <the recorded exact digest> --workers 4
```

The actual digest is read from the completed run manifest and must not be typed from memory.

- [ ] **Step 3: Monitor only liveness, task counts, errors, and process state**

Do not aggregate or interpret partial science. On failure, stop the experiment line and preserve the evidence without modifying settings or rerunning automatically.

---

### Task 4: Independently verify and seal the evidence

**Files:**
- Create at runtime: `results/23_camels_switch_confirmation/camels_parfc_state_interaction_01b_design90_s01_20260810_local/verification/`
- Create: `docs/plans/2026-08-10-camels-parfc-state-interaction-design90-01b-evidence.json`

**Interfaces:**
- Consumes: all 540 probability files, Arm-A legacy references, registered config and hashes, runner summaries, and empty/error logs.
- Produces: independently recomputed task, event, arm, direction, paired-comparison, and audit artifacts.

- [ ] **Step 1: Run the independent verifier in a new atomic verification directory**

- [ ] **Step 2: Independently confirm 540 tasks, 3,240 events, finite normalized probability and stable log probability, zero truth clipping, exact shared fields, and legacy Arm-A equality within `1e-12`**

- [ ] **Step 3: Report A, B, and C event counts, six directions, Brier score, stable negative-log score, paired signs, zero-probability frequency, and inherited scale-up gate**

- [ ] **Step 4: Hash the config, summaries, tables, logs, and probability-file collection, then write one completion evidence JSON**

- [ ] **Step 5: Stop at the review boundary**

Do not freeze validation settings, use seeds 2 or 3, run 531 basins, or claim state or forecast value. The next decision is a user review of Design90 evidence.

---

## Self-Review

- Specification coverage: selection correction, fixed science, seeds, three arms, fail-fast behavior, independent verification, evidence hashing, and claim boundaries are assigned to explicit tasks.
- Placeholder scan: no `TBD`, `TODO`, or unassigned implementation step remains. The command digest is deliberately sourced from the generated manifest rather than represented as a placeholder value.
- Type consistency: the verifier count helper supplies the same integer counts used by root, arm, task, event, direction, and legacy-reference checks.
- Execution choice: the user already supplied `GO`; this plan will be executed inline in the current task because no subagent execution skill is available and no delegation was requested.
