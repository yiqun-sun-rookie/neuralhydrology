# CAMELS-US parFC Overconfidence Diagnostic Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reproduce and causally decompose the extreme wrong-confidence episodes found in the verified 90-basin conservative parameter-state interaction arm without changing any scientific setting.

**Architecture:** Add one standalone diagnostic replay module that imports the registered runner's existing truth, filter-bank, and interaction functions but does not modify them. The module replays only the ten registered design-seed tasks whose stable true-candidate negative log probability exceeds 1000, captures model priors, candidate predictive observations, innovations, innovation variances, log likelihoods, and state/covariance moments, and verifies its posterior probabilities against the sealed Design90 files before writing an isolated output.

**Tech Stack:** Python 3.11, NumPy, pandas, pytest, existing HBV-lite modified unscented filters and interacting multiple-model implementation, SHA-256.

## Global Constraints

- Write only in `G:\wt\camels-rising`; preserve every existing dirty-tree file and result.
- Do not modify the registered hydrologic model, filter, state mapping, transition matrix, Design90 configuration, or sealed Design90 outputs.
- Use only the already used design seeds 0 and 1; do not use seeds 2 or 3 and do not run all 531 basins.
- Selection is explicitly outcome-driven diagnosis, not a representative sample and not new validation evidence.
- Create every diagnostic artifact exclusively; never overwrite or delete an existing file.
- No commit or push is authorized.

---

### Task 1: Freeze the diagnostic contract and selected failures

**Files:**
- Create: `docs/plans/2026-08-10-camels-parfc-overconfidence-diagnostic-prereg-v01.md`
- Create: `docs/plans/2026-08-10-camels-parfc-overconfidence-diagnostic-tasks-v01.csv`

**Interfaces:**
- Consumes: independently verified Design90 task metrics and C-arm probability files.
- Produces: the exact ten `(basin_id, seed)` tasks and fixed diagnostic quantities.

- [ ] **Step 1: Register selection without changing the threshold**

Select every C-arm task with stable true-candidate negative log probability strictly greater than 1000. Require exactly ten unique tasks and seeds drawn only from `{0,1}`.

- [ ] **Step 2: Register causal decomposition quantities**

For every day and candidate record predicted discharge, innovation, innovation variance, standardized squared innovation, log likelihood, predicted and posterior model probability, normalized log probability, pre-interaction state, destination-mixed state, predicted state, posterior state, the corresponding covariance diagonals, and soil-water/upper-groundwater covariance.

- [ ] **Step 3: Register severe-day and attribution rules**

A severe wrong-confidence day has true-candidate negative log probability greater than 100. Decompose winner-versus-truth posterior log odds into model-prior log odds, Gaussian residual contribution, and Gaussian log-variance contribution. Do not introduce clipping, likelihood floors, tempering, or alternative scores.

---

### Task 2: Implement a non-mutating diagnostic replay

**Files:**
- Create: `src/camels_switch_confirmation/diagnose_parameter_likelihood.py`
- Create: `test/test_camels_parameter_likelihood_diagnostic.py`

**Interfaces:**
- Consumes: parent Design90 configuration, parameter/precheck tables, raw CAMELS-US inputs, one registered C-arm reference probability file, and one task key.
- Produces: `select_extreme_tasks`, `decompose_gaussian_log_odds`, `replay_task`, and an exclusive command-line diagnostic runner.

- [ ] **Step 1: Write failing selection and decomposition tests**

Test exact threshold semantics, rejection of non-C rows or seeds outside `{0,1}`, and the identity
`posterior_log_odds = prior_log_odds + residual_contribution + log_variance_contribution`
to floating-point tolerance.

- [ ] **Step 2: Run the focused tests and retain the expected import failure**

Run:

```powershell
$env:PYTHONPATH=(Resolve-Path 'src').Path
& 'C:\Users\yiqun\anaconda3\python.exe' -m pytest -q test\test_camels_parameter_likelihood_diagnostic.py
```

Expected before implementation: collection failure because the diagnostic module does not exist.

- [ ] **Step 3: Implement the minimal pure helpers**

`select_extreme_tasks(frame, threshold=1000.0)` returns the sorted diagnostic task table. `decompose_gaussian_log_odds` returns prior, residual, log-variance, likelihood, and posterior terms and asserts closure within `1e-8` absolute tolerance.

- [ ] **Step 4: Test exact replay on one task**

Replay basin `05501000`, seed `1` with the unchanged C-arm contract. Require truth, observations, forcing, candidate vectors, posterior probabilities, and stable posterior log probabilities to match the sealed file within `1e-12`, with exact equality where the source generator is deterministic.

- [ ] **Step 5: Implement exclusive diagnostic output**

Write one compressed trace file per task, one daily candidate table, one severe-day table, one task summary, and one diagnostic summary. Refuse an existing output root, temporary root, task trace, or summary.

- [ ] **Step 6: Run focused and related regression tests**

The new tests plus the existing state-mapping, interaction, registered runner, run-integrity, and Design90 verifier tests must pass before configuration hashing.

---

### Task 3: Register and run the ten-task diagnostic

**Files:**
- Create: `src/camels_switch_confirmation/configs/camels_parfc_overconfidence_diagnostic_02_design10.json`
- Create: `docs/plans/2026-08-10-camels-parfc-overconfidence-diagnostic-registry-v01.csv`
- Create: `docs/plans/2026-08-10-camels-parfc-overconfidence-diagnostic-run-manifest-v01.json`
- Create at runtime: `results/23_camels_switch_confirmation/camels_parfc_overconfidence_diagnostic_02_design10_s01_20260810_local/`

**Interfaces:**
- Consumes: exact hashes of the parent configuration, parent task/event summaries, ten source probability files, diagnostic code, tests, preregistration, and task table.
- Produces: ten exact replays and attribution artifacts, or a nonzero stop preserving partial evidence.

- [ ] **Step 1: Hash every input and implementation file**

Require the parent Design90 configuration hash `1b5fed9c7958d719fefdbd3539993b3f5c567693e9be8032103698f5a1fbae13`, independent task metrics hash `99af08d732c327e7676c125b57cf351b81786c02f82cc04d223a56229f858ec1`, and all ten source probability-file hashes to match before creating output.

- [ ] **Step 2: Run the command once**

Use one process because only ten tasks are replayed and deterministic ordering simplifies auditing. Redirect standard output and error to new log paths.

- [ ] **Step 3: Stop on the first mismatch**

Any source probability difference above `1e-12`, input hash change, non-finite diagnostic value, non-positive innovation variance, existing output, or task exception stops the run without changing settings or retrying.

---

### Task 4: Determine the dominant failure mechanism and seal evidence

**Files:**
- Create: `docs/plans/2026-08-10-camels-parfc-overconfidence-diagnostic-02-evidence.json`

**Interfaces:**
- Consumes: all ten traces and the registered attribution formulas.
- Produces: one evidence-bounded cause classification and the next decision boundary.

- [ ] **Step 1: Verify all ten replays independently**

Confirm ten of ten tasks, 37,800 candidate-day rows, source probability/log-probability maximum difference at most `1e-12`, finite fields, and exact registered task coverage.

- [ ] **Step 2: Aggregate severe wrong-confidence days**

Report counts by stage, true candidate, winning candidate, and basin. Report median and upper-tail innovation, innovation variance, prior log-odds, residual contribution, and log-variance contribution.

- [ ] **Step 3: Classify only what the recorded quantities support**

Call the mechanism prediction-mean/path dominated only if the Gaussian residual term supplies most winner-versus-truth log odds; call it variance dominated only if the log-variance term supplies most. If neither is stable across severe days, report a mixed or unresolved cause.

- [ ] **Step 4: Preserve the decision boundary**

Do not implement a correction in this diagnostic. Any likelihood tempering, covariance inflation, state remapping change, or transition change requires a separately preregistered one-factor design-seed comparison and explicit user review before validation.

---

## Self-Review

- Specification coverage: selection, exact replay, causal decomposition, stop conditions, evidence, and seed boundaries each have an explicit task.
- Placeholder scan: no `TBD`, `TODO`, or unassigned implementation step remains.
- Type consistency: the per-candidate Gaussian terms use the same scalar innovation and innovation variance returned by the registered modified unscented filter.
- Execution choice: the user already provided `GO`; execution remains inline because the current collaboration policy does not authorize subagent delegation.
