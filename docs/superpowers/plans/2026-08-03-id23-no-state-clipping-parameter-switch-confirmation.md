# Parameter Switching Without State Clipping Implementation Plan

> **For agentic workers:** Execute this plan inline in the current isolated worktree. Do not dispatch subagents, stage files, commit, delete, reset, clean, or overwrite existing evidence. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and run one assimilation-only synthetic HBV-lite confirmation in which the true parameter vector switches at fixed stage boundaries while all fifteen truth-state values remain continuous and no truth-state projection or clipping occurs.

**Architecture:** A new experiment module owns candidate validation, truth generation, posterior-response scoring, and result summaries. A new runner freezes inputs and writes one isolated result directory. A separate verifier reimplements the truth equations and response calculations without importing the experiment module or runner. Human visual review is stored separately and combined with the numerical event decision only after the numerical result has been sealed.

**Tech Stack:** Python 3, NumPy, SciPy, Matplotlib, pytest, existing HBV-lite transition and interacting multiple-model filter primitives.

## Global Constraints

- Experiment ID: `g3_state_domain_consistent_parameter_switch_confirmation_v01`.
- User-facing Chinese name: “参数切换时不裁剪状态的正式确认实验”.
- Create new files and new result directories only; do not modify existing sealed results.
- Do not run forecasts, joint parameter-noise switching, state-interaction attribution, or real-basin evaluation.
- The only truth factor that switches is the fixed parameter candidate; process noise, observation noise, forcing contract, initial conditions, and candidate bank remain fixed.
- All three candidates use exactly the same `parFC` and `parCWH`; all other parameters remain within frozen HBV-lite bounds.
- Truth process noise is fixed to standard deviation 1 millimetre per day on lower groundwater storage only; the other fourteen truth-state process variances are zero.
- Candidate-construction seeds `3601001`-`3601008` are development-only and never enter formal scoring.
- Formal forcing, process-noise, and observation-noise seeds are `3701001`-`3701008`, `3702001`-`3702008`, and `3703001`-`3703008`.
- Candidate-construction and formal-confirmation seed sets must be disjoint from each other and from all protected earlier experiments.
- Every truth transition and every switch-boundary state check must have exactly zero projection adjustment.
- A numerical response requires five consecutive days within thirty days after switching with new-candidate posterior probability greater than `0.5` and probability margin over the runner-up at least `0.10`.
- A final event success is the intersection of the numerical response and a blinded visual classification of `clear_success`.
- Each directed transition requires at least `13/16` final successes and a two-sided exact 95 percent interval lower bound strictly greater than `0.5`.
- Any failed test, hash, source, physical, zero-projection, seed-independence, or independent-verification gate stops the experiment without a scientific conclusion.
- No Git staging or commits are permitted for this task.

---

### Task 1: Freeze the configuration and candidate vectors

**Files:**
- Create: `src/hbv_multilead_joint_uncertainty/configs/g3_state_domain_consistent_parameter_switch_confirmation_v01.json`

**Interfaces:**
- Consumes: sealed old parameter table and low observation-noise table with frozen SHA-256 values.
- Produces: one immutable JSON contract containing all thirteen parameter values plus lag time for three candidates, development and formal seeds, thresholds, and output paths.

- [ ] Verify every target path is absent and record the existing dirty worktree counts.
- [ ] Derive three candidates from the sealed old parameter vectors by replacing `parFC` and `parCWH` in every row with the trained-center values while leaving every other value unchanged.
- [ ] Record the exact old source hashes and the deterministic transformation rule in the JSON.
- [ ] Freeze development distinguishability gates: every pairwise deterministic discharge root-mean-square difference must exceed both five observation-error standard deviations and one-half of the trained-center discharge standard deviation.
- [ ] Freeze the numerical and visual event rules verbatim from the global constraints.
- [ ] Validate the JSON parses and all seed sets are unique and disjoint.

### Task 2: Implement truth generation and response scoring

**Files:**
- Create: `src/hbv_multilead_joint_uncertainty/state_domain_consistent_parameter_switch_confirmation.py`
- Test: `test/test_hbv_state_domain_consistent_parameter_switch_confirmation.py`

**Interfaces:**
- Produces: `build_rotating_parameter_schedule()`, `build_fixed_lower_groundwater_covariance()`, `audit_candidate_distinguishability()`, `generate_parameter_switch_truth()`, `first_complete_clear_dominance_run()`, `summarize_parameter_switch_response()`, `summarize_full_stage_accuracy()`, and `run_parameter_switch_confirmation()`.
- Returns: `ParameterSwitchConfirmationResult` containing forcing, schedules, random normals, all truth reconstruction arrays, observations, posterior probabilities, and global posterior states.

- [ ] Write tests proving the three 180-day cyclic schedules contain each directed transition sixteen times after eight blocks.
- [ ] Write tests proving candidate validation rejects unequal `parFC`, unequal `parCWH`, out-of-bound values, duplicate vectors, or non-finite values.
- [ ] Write tests proving the response function rejects rank-only near ties and accepts only five-day runs satisfying probability greater than `0.5` and margin at least `0.10`.
- [ ] Write tests proving exact-binomial intervals and the `13/16` gate match the frozen values.
- [ ] Implement truth propagation from the previous day’s full fifteen-state vector with the day’s active parameter candidate and the fixed lower-groundwater perturbation.
- [ ] Before every switched day’s forcing, project the unchanged previous state under the new parameters and require an exact zero adjustment.
- [ ] After every process perturbation, independently compute the projected state and require an exact zero adjustment before accepting the unprojected state as truth.
- [ ] Build one fully interacting three-filter bank with fixed parameter vectors and the same fixed covariance in every filter.
- [ ] Run the focused module tests with `PYTHONPATH=src` and require all to pass.

### Task 3: Implement the formal runner and immutable evidence package

**Files:**
- Create: `src/hbv_multilead_joint_uncertainty/scripts/run_g3_state_domain_consistent_parameter_switch_confirmation.py`
- Test: `test/test_hbv_state_domain_consistent_parameter_switch_confirmation_runner.py`

**Interfaces:**
- Consumes: frozen JSON configuration and sealed source tables.
- Produces: the isolated formal result directory, numeric tables, `evidence.npz`, forty-eight fixed-format event panels, source hashes, environment metadata, and `checksums.json`.

- [ ] Test that config validation rejects any changed experiment ID, seed, candidate value, threshold, result path, or source hash.
- [ ] Test that runner refuses existing formal or verification directories.
- [ ] Generate candidate-construction forcing only from development seeds and save only its aggregate audit, never its arrays, in the formal result.
- [ ] Generate formal forcing and noise only from the frozen formal seeds.
- [ ] Write event rows with probability, runner-up margin, numerical response start, and numerical success; do not include visual labels.
- [ ] Render forty-eight event panels on identical axes from day `-15` through day `+30`, mark the true switch, identify the new true candidate, and omit numerical pass/fail labels.
- [ ] Write a summary with status `complete_pending_blinded_visual_review_and_independent_verification` and withhold the scientific conclusion.
- [ ] Write all output to a new staging directory, validate required files and figure decoding, generate checksums last, and publish only when the target is still absent.
- [ ] Run the runner tests and require all to pass.

### Task 4: Run resource and physical preflight

**Files:**
- No new files; preflight is read-only with respect to formal output paths.

**Interfaces:**
- Consumes: frozen config and new experiment module.
- Produces: terminal evidence that candidate separation, seed independence, parameter bounds, switch-boundary projection, and all-transition projection gates pass.

- [ ] Run candidate construction on all eight development blocks and check all three pairwise separation gates.
- [ ] Run one formal block and all three truth rotations without writing formal results.
- [ ] Require zero switch-boundary projections, zero post-noise projections, finite fifteen-state truth, normalized probabilities, and no forecast imports.
- [ ] Stop without running the formal experiment if any preflight check fails.

### Task 5: Run and seal the numerical confirmation

**Files:**
- Create only through the runner: `results/23_hbv_multilead_joint_uncertainty/g3_state_domain_consistent_parameter_switch_confirmation_v01/`

**Interfaces:**
- Produces: all eight blocks, three truth rotations, 540 assimilation days, forty-eight numerical event decisions, and frozen visual panels.

- [ ] Recheck the target result and verification directories are absent immediately before execution.
- [ ] Execute the formal runner once.
- [ ] Verify the required-file set, artifact hashes, zero projections, finite arrays, probability normalization, and forty-eight event panels.
- [ ] Do not rerun with different seeds or thresholds after seeing results.

### Task 6: Perform and seal blinded visual review

**Files:**
- Create: `results/23_hbv_multilead_joint_uncertainty/g3_state_domain_consistent_parameter_switch_confirmation_v01_visual_review_v01/visual_review.csv`
- Create: `results/23_hbv_multilead_joint_uncertainty/g3_state_domain_consistent_parameter_switch_confirmation_v01_visual_review_v01/review_manifest.json`

**Interfaces:**
- Consumes: the forty-eight fixed-format event panels without numerical pass/fail labels.
- Produces: one immutable classification per event from `clear_success`, `ambiguous`, or `failure`, plus a short visible reason.

- [ ] Randomize display order with frozen seed `3704001` while retaining an auditable event mapping.
- [ ] Inspect every panel at original resolution before reading the numerical event decision.
- [ ] Classify `clear_success` only when the new candidate forms sustained, visibly separated post-switch dominance and was not already persistently dominant before the switch.
- [ ] Classify near ties, repeated alternating dominance, and isolated short episodes as `ambiguous` or `failure` with the reason recorded.
- [ ] Seal the forty-eight labels and their source-panel hashes before combining them with numerical decisions.

### Task 7: Implement and run independent verification

**Files:**
- Create: `src/hbv_multilead_joint_uncertainty/scripts/verify_g3_state_domain_consistent_parameter_switch_confirmation.py`
- Test: `test/test_hbv_state_domain_consistent_parameter_switch_confirmation_verifier.py`
- Create only through verifier: `results/23_hbv_multilead_joint_uncertainty/g3_state_domain_consistent_parameter_switch_confirmation_v01_independent_verification_v01/`

**Interfaces:**
- Consumes: frozen config, sealed formal evidence, and sealed visual review.
- Produces: `independent_verification.json` and its checksum manifest.

- [ ] Test the verifier rejects missing files, changed hashes, changed visual labels, projection events, probability normalization errors, or altered decision rules.
- [ ] Reimplement forcing, warmup, HBV-lite truth equations, process perturbations, projection adjustments, routed discharge, observations, clear-dominance runs, exact intervals, and final intersection decisions without importing the production experiment module or runner.
- [ ] Reconstruct all formal truth arrays with maximum absolute difference at most `1e-12` and require projection count `0` and maximum projection adjustment `0.0`.
- [ ] Recompute all numerical events from saved posterior probabilities, join the sealed visual classifications, and define final success as numerical success and `clear_success`.
- [ ] Require at least `13/16` final successes and exact interval lower bound above `0.5` in every direction for an all-direction supported conclusion.
- [ ] Run all focused tests, execute the verifier once, and stop without a scientific conclusion on any mismatch.

### Task 8: Final audit and reporting

**Files:**
- Create: `docs/plans/2026-08-03-id23-parameter-switch-without-state-clipping-closure.md`

**Interfaces:**
- Consumes: independently verified formal and visual evidence.
- Produces: one concise Chinese closure separating facts, inference, unknowns, and scope limits.

- [ ] Independently recompute all published counts, proportions, exact intervals, response days, full-stage top-ranked fractions, and mean true-candidate probabilities from sealed tables.
- [ ] Recheck all formal and verification checksums and confirm no protected path changed.
- [ ] Report each direction separately; do not hide a failed direction behind an overall average.
- [ ] State that the experiment is synthetic assimilation evidence only and provides no forecast, real-basin, process-noise-switch, joint-identification, or state-accuracy conclusion.
- [ ] Preserve all user changes and leave Git staging empty.
