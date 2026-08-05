# ID23 Single-State Contract Cleanup Implementation Plan

> **2026-08-01 semantic correction:** The standard fully interacting method
> already emits one unique global posterior state after every update. Rebuilding
> that probability-weighted state from model-conditionals is verification, not
> a new optional final-state publication rule. Model-conditioned trajectories
> remain diagnostics or ensemble controls.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the mis-scoped state-factorial experiment, replace it with an all-day direct combined-state error audit, and make the unique combined state the unambiguous primary forecast readout while retaining multi-trajectory averaging only as a labeled ensemble control.

**Architecture:** Historical three-stage synthetic evidence remains immutable and is used only as a source artifact. A new post-processing audit reads the sealed daily combined states and true states directly, evaluates every assimilation day without time-since-switch strata, and writes an isolated evidence package. Forecast code exposes one named primary readout and one explicitly named ensemble control without rewriting historical results.

**Tech Stack:** Python 3.11, NumPy, pytest, JSON/CSV evidence packages, MATLAB legacy scripts, Markdown handoffs.

**Execution status:** Completed on 2026-07-31. The direct audit and independent
recomputation passed; the targeted Python regression suites reported 70 and 11
passing tests, respectively.

## Global Constraints

- Do not alter any sealed historical result directory.
- Do not describe posterior-weighted parameters as true parameters that switch every day.
- The primary forecast form is one posterior-weighted combined state, one parameter readout, and one open-loop trajectory.
- Fixed calibrated parameters, posterior-weighted parameters, and maximum-posterior parameters are alternative single-trajectory parameter readouts.
- Multiple candidate trajectories followed by probability weighting are an ensemble forecast control, not the primary method.
- The direct state audit uses all 540 assimilation days as one primary population and contains no time-since-switch strata.
- Preserve unrelated dirty-worktree changes and do not create a commit.

---

### Task 1: Remove the mis-scoped state-factorial branch

**Files:**
- Delete: `docs/plans/2026-07-31-id23-state-update-factorial-design.md`
- Delete: `docs/plans/2026-07-31-id23-state-update-factorial-closure.md`
- Delete: `docs/superpowers/plans/2026-07-31-id23-state-update-factorial-implementation.md`
- Delete: `src/hbv_multilead_joint_uncertainty/configs/g3_state_update_factorial_development_v01.json`
- Delete: `src/hbv_multilead_joint_uncertainty/state_update_factorial.py`
- Delete: `src/hbv_multilead_joint_uncertainty/scripts/run_g3_state_update_factorial_development.py`
- Delete: `src/hbv_multilead_joint_uncertainty/scripts/verify_g3_state_update_factorial_development.py`
- Delete: `src/hbv_multilead_joint_uncertainty/scripts/verify_g3_state_update_factorial_development_recovery.py`
- Delete: `src/hbv_multilead_joint_uncertainty/scripts/finalize_g3_state_update_factorial_verification.py`
- Delete: `test/test_hbv_state_update_factorial.py`
- Modify: `src/hbv_joint_uncertainty/imm.py`
- Modify: `src/hbv_multilead_joint_uncertainty/methods.py`
- Modify: `test/test_hbv_joint_uncertainty_imm.py`
- Modify: `src/hbv_multilead_joint_uncertainty/configs/g3_experiment_registry.csv`

**Interfaces:**
- Consumes: the clean `full`, `parameter_grouped`, and `none` interaction modes at commit `935518ea`.
- Produces: the pre-factorial interaction API and registry with no completed state-factorial claim.

- [x] Remove only the files and result package whose experiment ID is `g3_state_update_factorial_development_v01`.
- [x] Revert the `mean_only` and `covariance_only` production interaction modes and their algebra test.
- [x] Remove only the matching registry row; retain the daily rolling readout row.
- [x] Verify `git diff` contains no unrelated reversal.

### Task 2: Add the all-day combined-state error audit

**Files:**
- Create: `src/hbv_multilead_joint_uncertainty/daily_combined_state_error.py`
- Create: `src/hbv_multilead_joint_uncertainty/configs/g3_daily_combined_state_error_audit_v01.json`
- Create: `src/hbv_multilead_joint_uncertainty/scripts/run_g3_daily_combined_state_error_audit.py`
- Create: `src/hbv_multilead_joint_uncertainty/scripts/verify_g3_daily_combined_state_error_audit.py`
- Create: `test/test_hbv_daily_combined_state_error.py`
- Modify: `src/hbv_multilead_joint_uncertainty/configs/g3_experiment_registry.csv`

**Interfaces:**
- Consumes: `method_assimilation_states`, `method_assimilation_probabilities`, `truth_states`, `parameter_vectors`, `method_names`, and `assimilation_days` from `g3_ideal_gate_param_switch_v01/evidence.npz`.
- Produces: `summarize_daily_combined_state_error(...) -> dict[str, np.ndarray]`, one result directory, and an independent verification report.

- [x] Write tests requiring one all-day mask of length 540 and rejecting any `switch_days`, `days_since_switch`, or time-stratum argument.
- [x] Implement direct daily errors for the five hydrologic states and all sealed methods.
- [x] Compute posterior-weighted parameter summaries for the parameter-only method at every day to document what actually changes daily.
- [x] Store all-day root-mean-square errors, daily root-mean-square error curves, block-level mean squared errors, and paired block-bootstrap intervals.
- [x] Add a runner that verifies the sealed source SHA-256 before producing an isolated evidence package.
- [x] Add an independent verifier that recomputes every saved metric from the sealed source rather than importing the runner’s summary function.
- [x] Register the audit as an `audit`, not as a new formal forecast experiment.

### Task 3: Make the single-state forecast contract explicit

**Files:**
- Modify: `src/hbv_multilead_joint_uncertainty/forecast_readout.py`
- Modify: `test/test_hbv_forecast_readout.py`
- Modify: `src/hbv_multilead_joint_uncertainty/configs/g3_daily_rolling_forecast_readout_development_v01.json`
- Modify: `docs/plans/2026-07-28-id23-daily-rolling-forecast-readout-design.md`
- Modify: `docs/plans/2026-07-28-id23-daily-rolling-forecast-readout-closure.md`

**Interfaces:**
- Consumes: the unchanged historical readout keys.
- Produces: `HISTORICAL_COVARIANCE_READOUT`, `ENSEMBLE_FORECAST_CONTROL`, `historical_covariance_prediction`, and `ensemble_control_prediction` without changing archived numerical arrays. The former primary aliases were removed on 2026-08-01 because they mislabeled a historical covariance-propagation control.

- [x] Add constants naming the posterior unique state plus posterior-weighted parameters as primary.
- [x] Label `current_multiple_states` as a legacy ensemble forecast control.
- [x] Historical step superseded on 2026-08-01: expose `historical_covariance_prediction` without a primary label, because this path propagates covariance and sigma points.
- [x] Update config metadata and documents so historical NO-GO results remain traceable but cannot define the primary method.

### Task 4: Remove misleading dead parameter assignments from legacy MATLAB forecasts

**Files:**
- Modify: the five `imm_mukf_forecast.m` copies under `forecast/scripts` and `for_submit/forecast/scripts`.
- Modify: the two noise-only `imm_forecast.m` copies.
- Modify: their seven `common_settings_forecast.m` files.
- Modify: `docs/draft4_reproduction_findings.md`
- Modify: `docs/handoff-2026-06-24-draft4-reproduction.md`

**Interfaces:**
- Consumes: the historical numerical contract, which forecasts one combined state with fixed calibrated parameter rows.
- Produces: behavior-identical MATLAB code with no false suggestion that weighted parameters enter the forecast.

- [x] Stop loading unused weighted parameter arrays in the affected forecast scripts.
- [x] Remove the dead assignments, including every `cq = cw` copy error.
- [x] Name the retained forecast parameter table `params_forecast_fixed` and document that this is one valid single-state forecast form.
- [x] Add comments where the forecast initial-condition table deliberately updates only the five state rows.
- [x] Confirm no executable line matching `params_rpn.cq = cw` remains.

### Task 5: Separate the current paper’s ensemble experiment from the primary single-state method

**Files:**
- Modify: `python/imm_da/experiment.py`
- Modify: `python/build_unified_manuscript.py`
- Modify: `paper/draft-7-unified.md`
- Modify: `docs/plans/2026-07-13-unified-main-full-progress.md`

**Interfaces:**
- Consumes: `run_imm_forecast` and `run_imm_forecast_per_filter`.
- Produces: explicit terminology: single-state forecast versus ensemble forecast control.

- [x] State in `run_imm_forecast` that it issues one trajectory from one combined state.
- [x] State in `run_imm_forecast_per_filter` that it is an ensemble control and cannot define the paper’s single-state method.
- [x] Remove language that silently presents independent candidate trajectory weighting as the generalized method’s only forecast form.
- [x] Preserve all old ensemble numerical claims only when labeled as the ensemble-control experiment.

### Task 6: Verify, record, and supersede memory

**Files:**
- Create: `C:/Users/yiqun/.codex/memories/extensions/ad_hoc/notes/20260731-id23-single-state-contract-correction.md`

**Interfaces:**
- Consumes: the final code, registry, result package, and protected-artifact hashes.
- Produces: a concise memory override and an auditable final report.

- [x] Run targeted unit tests for the direct state audit and forecast readout.
- [x] Run the audit and its independent verifier.
- [x] Run the relevant existing regression tests.
- [x] Verify protected historical artifact hashes remain unchanged.
- [x] Search code, documents, and memory for ambiguous uses of `current_multiple_states`, time-since-switch state conclusions, and dead weighted-parameter assignments.
- [x] Add an ad hoc memory note defining the corrected primary contract and the scope of retained staged evidence.
