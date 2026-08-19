# CAMELS-US Process-Noise-Only Switching Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement and run one exploratory CAMELS-US experiment in which all calibrated hydrologic parameters and observation noise remain fixed while only the true and candidate lower-groundwater process-noise standard deviation switches among `0.01`, `0.02`, and `0.04`.

**Architecture:** Add a dedicated `camels_process_noise_only` package rather than changing the completed parameter-switch runner. Refactor the shared interacting multiple-model class only enough to expose an explicit interaction-then-update boundary and stable log posterior probabilities; the new runner then assigns each noise candidate its own state-dependent, moment-matched process covariance after state interaction and before filtering. A separate verifier recomputes all decisive metrics from saved arrays without importing runner scoring helpers.

**Tech Stack:** Python 3, NumPy, pandas, pytest, existing HBV-lite state transition, modified unscented filters, and interacting multiple-model implementation.

## Global Constraints

- Write only inside `G:\wt\camels-rising`; keep `G:\github\pycharm\projects\neuralhydrology` read-only.
- Preserve every existing modified and untracked file; do not clean, reset, stage, commit, push, delete, or overwrite.
- Use design seeds `{0,1}` only. Do not use validation seeds `{2,3}`.
- Do not create or freeze a version 02 validation configuration and do not run all 531 basins.
- Keep all 13 calibrated center parameters, forcing, initial state, and basin-specific observation-noise standard deviation fixed throughout each task.
- Switch only the multiplicative lower-groundwater process-noise standard deviation in the truth; never switch observation noise.
- Use one experiment family, one design config snapshot, one output root per run, and one registry row per run.
- Abort on pre-existing output, changed input hash, incomplete forcing, candidate mismatch outside process noise, invalid truth index, non-finite values, probability sum error above `1e-12`, any truth-domain adjustment, test failure, or independent-verifier failure.
- Treat design-seed results as exploratory process-noise candidate-identification evidence only. Do not claim state accuracy, forecast value, real-observation assimilation value, or joint parameter-noise success.

---

## File Map

- Create `docs/plans/2026-08-09-camels-process-noise-only-prereg-v01.md`: human-readable preregistration and claim boundary.
- Create `docs/plans/2026-08-09-camels-process-noise-only-registry-v01.csv`: source-of-truth rows for smoke and 90-basin design runs.
- Create `docs/plans/2026-08-09-camels-process-noise-only-design90-basins-v01.csv`: deterministic 90-basin design list with selection provenance.
- Create `docs/plans/2026-08-09-camels-process-noise-only-design90-input-manifest-v01.csv`: SHA-256 manifest for every forcing and streamflow file read by the 90-basin design plus shared loader inputs.
- Create `docs/plans/2026-08-09-camels-process-noise-only-design90-manifest-v01.json`: exact hashes, command, and output mapping.
- Modify `src/hbv_joint_uncertainty/imm.py`: stable posterior log probabilities and public interaction/update split while preserving `step()` behavior.
- Create `src/camels_process_noise_only/__init__.py`: package description.
- Create `src/camels_process_noise_only/configs/camels_process_noise_only_01_design.json`: registered exploratory design config, explicitly not a validation freeze.
- Create `src/camels_process_noise_only/contract.py`: config validation, lognormal variance, truth schedule, basin selection, and fixed event/probability metric definitions.
- Create `src/camels_process_noise_only/runner.py`: truth generation, three identical-parameter filters, candidate-specific process covariance, isolated task execution, and CLI.
- Create `src/camels_process_noise_only/verifier.py`: independent integrity and scientific-metric recomputation.
- Create `test/test_camels_process_noise_only.py`: focused unit and integration-contract tests.
- Modify `test/test_hbv_joint_uncertainty_imm.py`: shared interacting multiple-model regression tests.

### Task 1: Register the exploratory design before code execution

**Files:**
- Create: `docs/plans/2026-08-09-camels-process-noise-only-prereg-v01.md`
- Create: `src/camels_process_noise_only/configs/camels_process_noise_only_01_design.json`
- Create: `docs/plans/2026-08-09-camels-process-noise-only-registry-v01.csv`

**Interfaces:**
- Consumes: the user-approved noise levels, 365-day stages, event rule, seed boundary, and current input paths.
- Produces: experiment ID `CAMELS_PROCESS_NOISE_ONLY_01`, a complete JSON config, and registry rows `CAMELS_PROCESS_NOISE_ONLY_01_SMOKE` and `CAMELS_PROCESS_NOISE_ONLY_01_DESIGN90`.

- [ ] **Step 1: Write the complete preregistration**

Record the exact truth formula

```text
S_t = S_tilde * exp(-sigma^2/2 + sigma*z_t), z_t ~ Normal(0,1)
```

the levels `[0.01, 0.02, 0.04]`, rotation `[1,0,2,1,2,0,1]`, seven 365-day stages, full interaction, transition diagonal `364/365`, uniform initial probabilities, fixed observation variance, design seeds `[0,1]`, and all success and stop gates.

- [ ] **Step 2: Write and validate the JSON design config**

The config must include exact values for inputs, truth, filter, event rule, probability metrics, design selection, bootstrap, seed streams, outputs, stop conditions, and prohibited claims. Set `configuration_status` to `registered_exploratory_design_not_validation_frozen`.

- [ ] **Step 3: Write registry rows before any run**

Use the schema:

```csv
exp_id,type,hypothesis,base_config,changed_factor,fixed_factors,seeds,status,run_dir,best_checkpoint,metrics_path,paper_name,notes
```

Set both run rows to `registered_not_run`; leave `best_checkpoint` empty because this experiment does not train a model.

### Task 2: Add stable log posterior probabilities and an interaction/update boundary

**Files:**
- Modify: `src/hbv_joint_uncertainty/imm.py`
- Modify: `test/test_hbv_joint_uncertainty_imm.py`

**Interfaces:**
- Produces: `normalize_log_weights_with_logs(log_weights) -> tuple[np.ndarray, np.ndarray]`, `InteractingMultipleModel.interact() -> np.ndarray`, and `InteractingMultipleModel.update_after_interaction(observation, prior_probabilities) -> InteractingStepResult`.
- Extends: `InteractingStepResult.posterior_log_probabilities` without changing existing `step()` numerical behavior.

- [ ] **Step 1: Write failing tests**

Test that extreme log weights can yield a zero stored probability while retaining a finite normalized log probability; test that `step()` equals `interact()` followed by `update_after_interaction()` for cloned filters; test invalid prior shapes and sums.

- [ ] **Step 2: Run the focused shared tests and confirm failure**

Run:

```powershell
& 'C:\Users\yiqun\anaconda3\python.exe' -m pytest -q test\test_hbv_joint_uncertainty_imm.py
```

Expected: failure because the new helper, result field, and public split do not exist.

- [ ] **Step 3: Implement stable normalization and the public split**

Compute normalized log probabilities with log-sum-exp, exponentiate only for ordinary probabilities, and preserve finite log values even when exponentiation underflows. Make `step()` call `interact()` and then `update_after_interaction()` so all old callers retain the same behavior.

- [ ] **Step 4: Run the shared tests**

Expected: all `test_hbv_joint_uncertainty_imm.py` tests pass.

### Task 3: Implement the frozen process-noise contract

**Files:**
- Create: `src/camels_process_noise_only/__init__.py`
- Create: `src/camels_process_noise_only/contract.py`
- Create: `test/test_camels_process_noise_only.py`

**Interfaces:**
- Produces: `load_design_config(path)`, `validate_design_config(config)`, `lognormal_variance(lower_state, sigma)`, `truth_candidate_indices(config)`, `select_design_basins(parameter_table, g1_table, config)`, `evaluate_event(probabilities, true_index, config)`, and `score_probabilities(probabilities, log_probabilities, truth_indices, config)`.

- [ ] **Step 1: Write failing contract tests**

Cover exact variance values, invalid sigma/state, exact 2555-day truth index schedule, balanced six target classes, fixed day 91-180 event scoring, the 60-of-90 daily rank gate, Brier/log-score baselines, classwise calibration, and deterministic 30-per-tertile basin selection.

- [ ] **Step 2: Run the new test file and confirm import failure**

Run:

```powershell
& 'C:\Users\yiqun\anaconda3\python.exe' -m pytest -q test\test_camels_process_noise_only.py
```

Expected: collection failure because the package is absent.

- [ ] **Step 3: Implement config validation and pure functions**

Reject any config that does not have exactly three finite positive noise levels `[0.01,0.02,0.04]`, seven 365-day stages, the approved rotation, design seeds `[0,1]`, full interaction, matched observation variance, or the approved event thresholds.

- [ ] **Step 4: Run contract tests**

Expected: all pure-function tests pass.

### Task 4: Implement the isolated runner

**Files:**
- Create: `src/camels_process_noise_only/runner.py`
- Modify: `test/test_camels_process_noise_only.py`

**Interfaces:**
- Produces: `generate_truth(...)`, `build_noise_bank(...)`, `run_one_task(...)`, `run_batch(...)`, and CLI `python -m src.camels_process_noise_only.runner`.
- Saves per task: ordinary and log probabilities, true candidate index, truth discharge, observations, all 15 truth states, standard-normal process draws, applied truth sigma, candidate lower-groundwater process variances, switch days, combined state, and all provenance scalars.

- [ ] **Step 1: Write failing runner tests**

Test mean-preserving positive truth noise, zero truth-domain adjustment, identical candidate parameters and initial moments, full interaction, candidate-specific moment-matched variances after interaction, exact fixed observation covariance, output refusal when a file exists, and finite normalized probabilities.

- [ ] **Step 2: Implement truth generation**

Advance the fixed center-parameter state once per day, apply the stage sigma only to lower groundwater, save the standard-normal draw and pre/post-noise state, and route discharge from the post-transition routing memory exactly as in the completed parameter line.

- [ ] **Step 3: Implement the three-candidate filter bank**

Give all filters byte-identical parameters, initial state, initial covariance, forcing transition, and observation covariance. Use full interaction. After `estimator.interact()`, deterministically advance each mixed candidate state, set only covariance entry `[4,4]` to

```python
predicted_lower_groundwater**2 * np.expm1(candidate_sigma**2)
```

then call `update_after_interaction()`.

- [ ] **Step 4: Implement batch execution and output isolation**

Require an unused output root, load only basins in the frozen list, require exactly 2555 finite forcing days, and write each task atomically through a task-specific temporary filename followed by `Path.replace()`.

- [ ] **Step 5: Run runner tests**

Expected: all focused tests pass and existing parameter-switch tests remain unchanged.

### Task 5: Implement independent verification

**Files:**
- Create: `src/camels_process_noise_only/verifier.py`
- Modify: `test/test_camels_process_noise_only.py`

**Interfaces:**
- Produces CLI `python -m src.camels_process_noise_only.verifier --run-dir PATH --config PATH --expected-tasks N` and files `verification.json`, `events.csv`, and `scientific_summary.json` only when the target names do not already exist.

- [ ] **Step 1: Write failing verifier tests**

Use synthetic temporary probability files to test task count, exact basin/seed set, true-index schedule, finite arrays, probability normalization, log/probability agreement where representable, zero truth-domain adjustment, candidate variance trace, event metrics, uniform baselines, and deliberate corruption rejection.

- [ ] **Step 2: Implement verifier without importing runner metric helpers**

Recompute event decisions directly from saved arrays. Calculate post-switch day 181-365 multiclass Brier score, log-domain true-candidate negative log probability, classwise 10-bin calibration error, seed agreement, six directional pass rates, and 10,000 basin-cluster percentile bootstrap intervals with bootstrap seed `20260809`.

- [ ] **Step 3: Run verifier tests**

Expected: all corruption cases stop with a nonzero exit and valid fixtures pass.

### Task 6: Create and freeze the deterministic 90-basin design list

**Files:**
- Create: `docs/plans/2026-08-09-camels-process-noise-only-design90-basins-v01.csv`
- Create: `docs/plans/2026-08-09-camels-process-noise-only-design90-input-manifest-v01.csv`
- Create: `docs/plans/2026-08-09-camels-process-noise-only-design90-manifest-v01.json`

**Interfaces:**
- Consumes: current rising-parameter table and G1 precheck table.
- Produces: 90 basin IDs, 30 from each fixed proxy tertile, with SHA-256 recorded in the manifest.

- [ ] **Step 1: Generate the list with the tested selector**

Compute

```text
rho = parK2 * max(parPERC/parK2, 1) * sqrt(expm1(0.02^2)) / sigma_obs
```

sort by `(rho, basin_id)`, split the 531 rows into consecutive groups of 177, and take 30 rounded equally spaced zero-based positions from each group.

- [ ] **Step 2: Independently verify the list**

Require 90 unique IDs, 30 per tertile, no missing inputs, exact deterministic rank positions, and a stable SHA-256. Record the parameter table, G1 table, config, runner, shared IMM module, and basin-list hashes in the manifest.

- [ ] **Step 3: Hash every file read by the data loader and verify coverage**

For each selected basin, hash the exact Maurer forcing file and streamflow file resolved by the loader. Also hash `camels_topo.txt` and `src/hydroagent/data_loading.py`. Load the registered 1989-10-01 through 1996-09-28 window and require exactly 2555 finite forcing days for all 90 basins before any experiment starts.

### Task 7: Execute tests and one-basin smoke

**Files:**
- Create: `results/23_camels_process_noise_only/camels_process_noise_only_01_smoke_basin09306242_s01_20260809/`

**Interfaces:**
- Consumes: design config and first frozen design basin.
- Produces: two tasks for seeds 0 and 1 plus independent verification.

- [ ] **Step 1: Run focused and shared regression tests**

Run:

```powershell
& 'C:\Users\yiqun\anaconda3\python.exe' -m pytest -q test\test_camels_process_noise_only.py test\test_camels_switch_confirmation.py test\test_hbv_joint_uncertainty_imm.py
```

Stop on any failure.

- [ ] **Step 2: Confirm smoke output root is absent and run one basin**

Use `--limit 1 --workers 1 --seeds 0 1` and the dedicated smoke output root.

- [ ] **Step 3: Run the independent verifier**

Require 2/2 tasks, 12 events, zero truth-domain adjustments, finite normalized probabilities, exact metadata, and verifier success. Do not use smoke scientific metrics for claims.

### Task 8: Run and verify the 90-basin exploratory design

**Files:**
- Create: `results/23_camels_process_noise_only/camels_process_noise_only_01_design90_s01_20260809/`

**Interfaces:**
- Consumes: exact 90-basin list, design seeds 0 and 1, tested runner, and manifest hashes.
- Produces: 180 atomic task files, runner summary/logs, independent verification, 1,080 event decisions, and exploratory scientific metrics.

- [ ] **Step 1: Recheck hashes, tests, processes, and unused output**

Abort if any manifest input hash changed, a CAMELS process is active, tests no longer pass, or the output root exists.

- [ ] **Step 2: Run the design batch**

Use two workers and seeds 0 and 1 only. Never overlap with another CAMELS run.

- [ ] **Step 3: Independently verify all artifacts**

Require 180/180 successful tasks, 1,080 events, 90 unique basins, zero truth-domain adjustments, finite arrays, probability-sum maximum error at most `1e-12`, exact candidate metadata, and all manifest hashes.

- [ ] **Step 4: Apply the preregistered scientific gate once**

Require every event, interval, seed-agreement, Brier, log-score, and calibration threshold. A single failed threshold yields `not_passed`; secondary metrics cannot rescue it.

- [ ] **Step 5: Stop for user review**

Report exploratory results and evidence paths. Do not create a validation freeze and do not run seeds 2 or 3 or all 531 basins.

## Self-Review

- Spec coverage: the plan covers exact noise levels, moment matching, stage schedule, event window, probability and calibration metrics, design/validation seed separation, deterministic 90-basin selection, full interaction, zero-projection audit, isolated outputs, independent verification, and claim boundaries.
- Placeholder scan: no implementation field is left undefined; every threshold, path, seed, and formula is explicit.
- Type consistency: the runner consumes the public `interact()` and `update_after_interaction()` methods introduced in Task 2; verifier inputs are exactly the arrays saved in Task 4; Task 6 list and Task 8 manifest use the same config and hash contract.
- Authorization: this plan deliberately ends after the 90-basin design and user review. Formal validation remains outside the current GO.
