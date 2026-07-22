# HBV fifteen-state correction propagation implementation plan

> **Execution rule:** Follow test-first implementation and preserve every failed run under a new identifier. Do not commit or push.

**Goal:** Explain why discharge-driven state correction degrades the three-day and seven-day retrospective forecasts while keeping the frozen sixteen basins, 358 common origins, meteorology, parameter vectors, process-noise candidates, and five reference methods unchanged.

**Architecture:** Reconstruct the hidden origin prior and posterior state means by replaying only the frozen nine-candidate joint method against the immutable formal contract and result snapshots. Write a separate diagnostic implementation so the 37 source files bound to the formal result remain byte-identical. Evaluate a preregistered set of state-update controls and save every state mean needed for an independent reconstruction.

**Technology:** Python, NumPy, pandas, pytest, the existing Hydrologiska Byråns Vattenbalansavdelning fifteen-state adapter, the existing modified unscented filter, and the existing resource recorder.

---

## Frozen scientific boundary

- Formal contract: `results/23_hbv_multilead_joint_uncertainty/formal_contract_sixteen_v05`
- Formal contract checksum-table hash: `c7615c868b747d1b633eb5d32432376b5648087846d97d0ff5fa507ecdf4c357`
- Formal result: `results/23_hbv_multilead_joint_uncertainty/formal_result_sixteen_v01`
- Formal result checksum-table hash: `88ab2297e02179cc0e3e432c958871e1d6e7985358b9394970154a65f2348bd0`
- Basins: the exact sixteen basin identifiers in the formal contract, in contract order.
- Evaluation dates: 1989-10-01 through 1990-09-30.
- Forecast leads: 1, 3, and 7 days over the exact 358 common origins.
- Future forcing: historical observed meteorology used only for retrospective diagnosis; it must never be described as an operational forecast.
- Future discharge: forbidden after each origin. A perturbation test must show zero change for already issued forecasts.
- Formal artifacts, reproduction sessions, shards, aggregations, and their logs are read-only.

## Preregistered controls

No result from the evaluation period may change these controls or their status.

1. `current_joint_all_fifteen_states`: exact reconstruction of the frozen joint method; all fifteen states receive the discharge update. This is the reference, not a selectable candidate.
2. `hydrologic_five_states_only`: only snowpack, snow liquid water, soil water, upper storage, and lower storage receive discharge updates throughout the evaluation; all ten routing-memory states are locked during measurement updates.
3. `runoff_two_states_only`: only upper storage and lower storage receive discharge updates throughout the evaluation; the other thirteen states are locked during measurement updates.
4. `origin_update_removed`: for each forecast origin, retain the frozen posterior candidate probabilities but replace that origin's candidate posterior state and covariance with its candidate prior state and covariance. This is a diagnostic counterfactual, not a candidate for the continuation gate.
5. `three_day_half_life_state_decay`: after independently propagating the reference and `origin_update_removed` branches, blend candidate state means at each target as
   `removed_state + retention * (reference_state - removed_state)`.
   Retention is fixed before evaluation as `2 ** (-(lead_days - 1) / 3)`, giving exactly `1.0`, `0.6299605249474366`, and `0.25` at one, three, and seven days. Candidate covariance uses the same convex blend. Candidate probabilities remain the frozen reference probabilities. This is the only control allowed to decide the continuation gate.

The two state-locking controls answer which state groups may receive discharge updates. The target-state decay control answers whether the isolated origin correction should weaken with lead. They do not change parameter candidates, process-noise candidates, observation noise, transition probabilities, meteorology, basin count, or model structure.

## Required saved arrays per basin

- Formal common arrays and all five formal method arrays, copied only after exact checksum verification.
- Fifteen state names and every control's fifteen-element update mask.
- Candidate origin prior states, posterior states, state corrections, prior covariance diagonals, and posterior covariance diagonals.
- Origin prior probabilities and posterior probabilities.
- Combined prior states, combined posterior states, probability-reweighting contribution, and state-update contribution.
- Reference and `origin_update_removed` candidate states at one, three, and seven days.
- Reference and `origin_update_removed` combined states at one, three, and seven days.
- Every control's candidate predictions, combined predictions, probabilities, candidate state means, combined state means, candidate covariance diagonals, and combined covariance diagonals.
- Exact one-, three-, and seven-day target observations and dates.
- The actual lead-specific state-retention values.

## Task 1: Write failing filter-state masking checks

**Files:**

- Create: `test/test_hbv_state_correction_diagnostic.py`
- Create later: `src/hbv_multilead_joint_uncertainty/state_correction_diagnostic.py`

1. Write a two-state nonlinear-filter test showing that a weight vector `[1, 0]` changes only the first posterior mean.
2. Require the locked state's posterior mean to equal its prior mean exactly.
3. Require the partial-update covariance to be symmetric, finite, and positive semidefinite within `1e-12`.
4. Require an all-ones weight vector to be bitwise identical to the existing filter update.
5. Run only these checks and confirm failure because the diagnostic filter does not exist.

## Task 2: Implement the isolated weighted-update filter

**Files:**

- Create: `src/hbv_multilead_joint_uncertainty/state_correction_diagnostic.py`

1. Subclass the existing modified unscented filter in the new module; do not edit the frozen formal source files.
2. Delegate an all-ones update to the existing implementation for exact reference reconstruction.
3. For partial weights, use the weighted gain in the mean update and the full covariance expression with both cross-covariance terms.
4. Project the posterior state through the existing physical-state projector.
5. Run the Task 1 checks and require all to pass.

## Task 3: Write failing origin-state and propagation checks

**Files:**

- Modify: `test/test_hbv_state_correction_diagnostic.py`

1. Require common origin and target indices to remain exactly 358 by 3 for a 365-day evaluation.
2. Require the reference branch to retain candidate origin priors, posteriors, and all fifteen target state means.
3. Require `origin_update_removed` to start from the candidate prior state while retaining posterior probabilities.
4. Require the reference branch not to mutate the continuing assimilation bank.
5. Require one-day state decay to be exactly identical to the reference state and prediction.
6. Require future-discharge perturbation after each origin to produce exactly zero change in issued predictions.
7. Run these checks and confirm failure because the runner and result structures do not exist.

## Task 4: Implement the per-basin reconstruction and controls

**Files:**

- Modify: `src/hbv_multilead_joint_uncertainty/state_correction_diagnostic.py`

1. Build the frozen nine-candidate joint bank from one basin contract.
2. Replay the reference bank and the two state-locking banks through each origin.
3. Capture the complete candidate result before any summary discards state means.
4. Forecast the reference, the two state-locking controls, and the origin-update-removed counterfactual without future discharge.
5. Construct the fixed target-state decay control from propagated states, covariances, and reference probabilities.
6. Verify the reference predictions, candidate predictions, probabilities, and covariance diagonals against the frozen saved arrays with maximum absolute difference no greater than `1e-12`.
7. Return all arrays without writing.
8. Run Task 3 checks and require all to pass.

## Task 5: Write failing package, registry, checksum, and resource checks

**Files:**

- Modify: `test/test_hbv_state_correction_diagnostic.py`
- Create later: `src/hbv_multilead_joint_uncertainty/scripts/run_state_correction_diagnostic.py`
- Create later: `src/hbv_multilead_joint_uncertainty/configs/state_correction_propagation_v01.json`

1. Require a new run identifier and refuse every existing output, incomplete output, failed output, log, or registry identifier.
2. Require exact formal contract and formal result checksum-table hashes before reading basin arrays.
3. Require the formal sixteen-basin order, five methods, three leads, and 358 origins.
4. Require start memory at least 25%, running memory at least 20%, estimated peak at most 60% of start-available memory, one numerical thread, two reserved logical processors, 50 gibibytes free disk, and three times estimated output size.
5. Require resource samples no more than 15.5 seconds apart and a terminal finish record.
6. Require serial basin completion order.
7. Require atomic publication, failure preservation, source snapshots, input references, and checksum verification.
8. Run these checks and confirm failure because packaging and the command-line entry point do not exist.

## Task 6: Implement the atomic experiment package

**Files:**

- Modify: `src/hbv_multilead_joint_uncertainty/state_correction_diagnostic.py`
- Create: `src/hbv_multilead_joint_uncertainty/scripts/run_state_correction_diagnostic.py`
- Create: `src/hbv_multilead_joint_uncertainty/configs/state_correction_propagation_v01.json`

1. Freeze the controls, hashes, resource thresholds, basin list, and continuation rule in the configuration file.
2. Reserve the run identifier before creating an incomplete directory.
3. Start the existing background resource recorder before semantic verification or numerical work.
4. Process basins strictly in frozen contract order with one numerical thread.
5. Write one compressed array file per basin immediately.
6. Generate state-level correction summaries, state-propagation summaries, control metrics, paired basin comparisons, and the continuation decision.
7. Snapshot every used source file and record every formal input and result hash.
8. Verify all saved arrays and summaries independently before atomic publication.
9. Preserve a failed directory and failed registry history for every exception, including resource-gate failures.
10. Run Task 5 checks and the existing hydrologic joint-uncertainty tests.

## Task 7: Run a one-basin controlled experiment

Use the first frozen formal basin only for execution validation; do not use its metrics to change any control.

- Experiment identifier: `state_correction_smoke_12143600_v01`
- Output root: `results/23_hbv_multilead_joint_uncertainty/state_correction_smoke_12143600_v01`
- Log root: `logs/23_hbv_multilead_joint_uncertainty/state_correction_smoke_12143600_v01`

Before starting, record and enforce all resource gates. After completion, verify exact reference reconstruction, array completeness, future-discharge isolation, checksums, and report arithmetic.

## Task 8: Independent smoke code-and-result review

- Review identifier: `state_correction_smoke_12143600_v01_audit_v01`
- Review directory: `results/23_hbv_multilead_joint_uncertainty/independent_audits/state_correction_smoke_12143600_v01_audit_v01`

The reviewer must independently recompute saved summaries from arrays, inspect source without trusting implementation claims, perturb future discharge, check masks and retention values, and record each finding with file, evidence, severity, and pass or fail status.

A second independent context must reproduce every reported finding. If a finding is not reproduced, save the counterevidence and do not change code. If a finding is reproduced, write a failing regression check, create a new experiment identifier, implement one fix, and rerun the smoke experiment without modifying the failed or superseded artifacts.

## Task 9: Run the frozen sixteen-basin experiment

Only after the smoke review has zero unresolved blocking findings:

- Experiment identifier: `state_correction_formal_sixteen_v01`
- Process all sixteen basins serially in contract order.
- Use all 358 origins and the exact one-, three-, and seven-day targets.
- Do not run any basin outside the formal sixteen.

## Task 10: Independent formal review and continuation decision

- Review identifier: `state_correction_formal_sixteen_v01_audit_v01`
- Independently recompute every state summary, metric, basin comparison, and gate value from saved arrays.
- Independently verify any review finding before a fix.
- End by comparing the evidence with the single target: long-lead propagation of origin state correction.

The continuation gate is evaluated only for `three_day_half_life_state_decay`:

1. Seven-day within-basin paired root-mean-square-error change relative to the no-state-update original model has median at most `0%`.
2. At least `9` of `16` basins have strictly lower seven-day root-mean-square error than the no-state-update original model.
3. One-day root-mean-square-error increase relative to the frozen current joint method is at most `1%`.

All three conditions must pass. Otherwise the conclusion is **stop**, and no 531-basin run is permitted.
