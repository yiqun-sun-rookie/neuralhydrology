# State-Domain-Consistent Process-Noise Switch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and formally run an assimilation-only synthetic experiment that tests whether a three-filter interacting multiple-model bank follows known switches among three lower-groundwater process-noise levels when the truth receives exact additive Gaussian perturbations and requires zero truth-state clipping.

**Architecture:** Add one experiment-specific module that generates a continuous three-stage truth and runs only the three process-noise filters with the complete `trained_center` HBV parameter vector fixed. A dedicated runner freezes inputs, seeds, gates, isolated output, raw evidence, tables, and plots; a structurally independent verifier reconstructs truth and decisions from saved arrays without importing the production experiment module. Forecast modules and forecast trajectories are forbidden.

**Tech Stack:** Python 3, NumPy, SciPy, Matplotlib, pytest, existing fifteen-state HBV-lite adapter and interacting multiple-model implementation.

## Global Constraints

- Work only in `G:\wt\id23-readout`; preserve all pre-existing tracked and untracked changes.
- Do not clean, reset, restore, stage, commit, delete, or overwrite user files.
- Experiment ID is `g3_state_domain_consistent_process_noise_switch_v01`; one frozen config and one new result root use that exact ID.
- Fixed model parameter vector is `trained_center`; only the lower-groundwater process-noise standard deviation changes among `1.0`, `4.0`, and `16.0` mm per day.
- All other fourteen state-noise variances are exactly zero; the lower-groundwater variances are `1.0`, `16.0`, and `256.0` square millimetres.
- Synthetic forcing is fixed before filtering: rain is `5 + Gamma(shape=0.8, scale=4.0)` mm/day, potential evaporation is `2.0` mm/day, and temperature is `10.0` degrees Celsius.
- Use eight fresh matched blocks, 90 warm-up days, three 180-day stages, two switches per truth trial, and three rotated truth trials.
- Truth state is continuous across switches and is never reset. Only the process-noise covariance label changes.
- Hard truth-validity gate: projection-event count equals `0` and maximum absolute projection adjustment equals `0.0`; otherwise stop before scientific interpretation.
- Primary prospective response definition: within 30 days after each switch, the new true noise candidate is top-ranked for one complete run of five consecutive days.
- Per directed transition, require at least `13/16` successful matched events and an exact two-sided 95% Clopper-Pearson interval lower bound strictly above `0.5`.
- No forecast import, forecast calculation, future observation, or forecast conclusion is permitted.
- A failed unit test, formal integrity gate, or independent verification stops the workflow and yields no scientific conclusion.
- Generated plots use a colour-blind-safe blue/orange/green palette and must be decoded and visually inspected.
- The implementation plan is executed inline because the user already gave an explicit GO; no subagent or commit is authorized.

---

### Task 1: Freeze the experiment contract and failing tests

**Files:**
- Create: `src/hbv_multilead_joint_uncertainty/configs/g3_state_domain_consistent_process_noise_switch_v01.json`
- Create: `test/test_hbv_state_domain_consistent_process_noise_switch.py`
- Create: `test/test_hbv_state_domain_consistent_process_noise_switch_runner.py`
- Create: `test/test_hbv_state_domain_consistent_process_noise_switch_verifier.py`

**Interfaces:**
- Consumes: sealed `g3_ideal_gate_param_switch_v01/parameter_vectors.csv` and `g3_ideal_inputs_v01/observation_noise_low.csv` with exact SHA-256 values recorded in the config.
- Produces: one frozen JSON contract and failing tests for the module, runner, and verifier interfaces listed below.

- [ ] **Step 1: Record the current dirty-worktree status, source hashes, target-path absence, and available memory before editing.**

Run:

```powershell
git status --short
Get-FileHash -Algorithm SHA256 results\23_hbv_multilead_joint_uncertainty\g3_ideal_gate_param_switch_v01\parameter_vectors.csv
Get-FileHash -Algorithm SHA256 results\23_hbv_multilead_joint_uncertainty\g3_ideal_inputs_v01\observation_noise_low.csv
Test-Path results\23_hbv_multilead_joint_uncertainty\g3_state_domain_consistent_process_noise_switch_v01
```

Expected: the worktree is dirty, both hashes match the new config, and the target result path is `False`.

- [ ] **Step 2: Create the frozen config with exact factors, seeds, response rule, integrity gates, forbidden forecast scope, protected paths, and output ID.**

The config must include `status: frozen_before_run`, `fixed_parameter_id: trained_center`, three named lower-groundwater noise candidates, block seeds `3501001..3501008`, `3502001..3502008`, and `3503001..3503008`, and `forecast_executed: false`.

- [ ] **Step 3: Write failing tests for schedule rotation, covariance support, zero-projection rejection, response-run detection, exact interval decisions, config validation, existing-output rejection, and forbidden forecast imports.**

Required production signatures:

```python
def build_rotating_process_schedule(process_ids: Sequence[str], stage_length_days: int) -> np.ndarray: ...
def build_lower_groundwater_process_covariances(standard_deviations: Mapping[str, float]) -> dict[str, np.ndarray]: ...
def first_complete_top_ranked_run(top_ranked: np.ndarray, consecutive_days: int, window_days: int) -> int | None: ...
def exact_binomial_interval(successes: int, total: int, confidence_level: float = 0.95) -> tuple[float, float]: ...
def summarize_switch_response(probabilities: np.ndarray, process_schedule: np.ndarray, process_ids: Sequence[str], response_window_days: int, consecutive_top_days: int, minimum_successful_events: int, minimum_interval_lower_bound: float) -> tuple[list[dict], list[dict]]: ...
```

- [ ] **Step 4: Run the focused tests and confirm they fail because the new modules do not yet exist.**

Run:

```powershell
$env:PYTHONPATH=(Resolve-Path 'src').Path
python -m pytest test/test_hbv_state_domain_consistent_process_noise_switch.py test/test_hbv_state_domain_consistent_process_noise_switch_runner.py test/test_hbv_state_domain_consistent_process_noise_switch_verifier.py -q
```

Expected: collection fails only for the absent new implementation modules.

### Task 2: Implement assimilation-only clean truth and process-noise filtering

**Files:**
- Create: `src/hbv_multilead_joint_uncertainty/state_domain_consistent_process_noise_switch.py`
- Test: `test/test_hbv_state_domain_consistent_process_noise_switch.py`

**Interfaces:**
- Consumes: validated forcing `(blocks, 630, 3)`, fixed HBV parameters, three diagonal covariances, process and observation seeds, and response thresholds.
- Produces: `StateDomainConsistentProcessNoiseSwitchResult` containing forcing, schedules, normals, deterministic truth states, exact perturbations, projection audits, truth states/discharge, observations, posterior probabilities, and unique global posterior states.

- [ ] **Step 1: Implement input validation, the three rotated schedules, and lower-groundwater-only diagonal covariances.**

The process schedule must contain three truth trials and use stage orders `[medium, high, low]`, `[high, low, medium]`, and `[low, medium, high]`, which provide 16 matched events for each directed transition across eight blocks.

- [ ] **Step 2: Implement truth generation without accepting projected states.**

For each day compute `deterministic_state`, add the saved Gaussian perturbation only at state index `4` (`SLZ`), calculate `project_reference_state(unprojected_state) - unprojected_state`, and raise `ValueError('truth state-domain gate failed')` if any component is nonzero. Commit the unprojected state directly when the gate passes.

- [ ] **Step 3: Implement the three-filter assimilation loop.**

Build only `definitions['noise_only']` with `trained_center` parameters, full state/covariance interaction, transition probability `0.98`, identical daily forcing and observation, and one posterior-probability-weighted fifteen-state global posterior after every update. Do not import or call any forecast module.

- [ ] **Step 4: Implement prospective switch-response scoring and descriptive full-stage accuracy.**

Create one event row per method-transition-block-truth-boundary combination and one summary row per directed transition. Use the exact new-candidate index, days `0..29`, complete five-day runs starting at `0..25`, and exact Clopper-Pearson intervals.

- [ ] **Step 5: Run the module tests and confirm they pass.**

Run:

```powershell
$env:PYTHONPATH=(Resolve-Path 'src').Path
python -m pytest test/test_hbv_state_domain_consistent_process_noise_switch.py -q
```

Expected: all module tests pass.

### Task 3: Implement the atomic runner and evidence package

**Files:**
- Create: `src/hbv_multilead_joint_uncertainty/scripts/run_g3_state_domain_consistent_process_noise_switch.py`
- Test: `test/test_hbv_state_domain_consistent_process_noise_switch_runner.py`

**Interfaces:**
- Consumes: the frozen config and module result.
- Produces: one new atomic result directory with `evidence.npz`, `summary.json`, `switch_response_summary.csv`, `switch_response_events.csv`, `daily_probabilities.csv`, `probability_response.png`, `response_summary.png`, `config_snapshot.json`, source inputs, environment, source snapshot, `registry_entry.json`, and `checksums.json`.

- [ ] **Step 1: Implement fail-closed config, source-hash, protected-path, output-absence, and resource checks.**

The runner must reject any config change to the experiment ID, fixed parameter, noise support, standard deviations, seeds, stage lengths, zero-projection gate, response criterion, or forbidden forecast fields.

- [ ] **Step 2: Implement deterministic forcing and exact source loading.**

Generate 630 days per block from the frozen forcing seeds. Load all parameter rows for bank construction but select only `trained_center` for truth and the three process-noise filters.

- [ ] **Step 3: Implement atomic execution and artifact writing.**

Write first to `<experiment_id>.incomplete.<uuid>`, verify all numeric arrays are finite, require the truth projection gates to be exactly zero, decode both PNGs, then rename to the final result path only if every gate passes. Never replace an existing path.

- [ ] **Step 4: Implement accessible probability and response-summary plots.**

The probability plot has three rows for the three directed transitions, shows the median of 16 events from day `-15` through day `+29`, marks day `0`, and labels the prospectively frozen success count and exact interval. The summary plot shows observed response fractions with exact intervals and the `13/16` threshold.

- [ ] **Step 5: Run runner tests and import-scope tests.**

Run:

```powershell
$env:PYTHONPATH=(Resolve-Path 'src').Path
python -m pytest test/test_hbv_state_domain_consistent_process_noise_switch_runner.py -q
```

Expected: all runner tests pass and importing the runner reports no loaded module name containing `forecast` under `hbv_multilead_joint_uncertainty`.

### Task 4: Implement structurally independent verification

**Files:**
- Create: `src/hbv_multilead_joint_uncertainty/scripts/verify_g3_state_domain_consistent_process_noise_switch.py`
- Test: `test/test_hbv_state_domain_consistent_process_noise_switch_verifier.py`

**Interfaces:**
- Consumes: the sealed result directory only.
- Produces: a separate unused verification directory `g3_state_domain_consistent_process_noise_switch_v01_independent_verification_v01` containing `independent_verification.json` and its own checksum.

- [ ] **Step 1: Implement independent hash and schema checks without importing the production experiment module.**

Require every `checksums.json` entry to exist and match, verify source hashes against the config snapshot, and reject shape, label, or probability-sum mismatches.

- [ ] **Step 2: Independently reconstruct truth and observations from forcing, normals, fixed parameters, covariance schedule, and observation noise.**

Recompute all 12,960 assimilation truth transitions and require maximum differences of `0.0` for deterministic states, perturbations, projection adjustments, truth states, truth discharge, and observations.

- [ ] **Step 3: Independently recompute every response event, exact interval, transition decision, and overall decision.**

Compare all CSV and JSON fields at absolute tolerance `1e-12`; require the verifier to fail if any saved decision differs.

- [ ] **Step 4: Run verifier tests and import-scope tests.**

Run:

```powershell
$env:PYTHONPATH=(Resolve-Path 'src').Path
python -m pytest test/test_hbv_state_domain_consistent_process_noise_switch_verifier.py -q
```

Expected: all verifier tests pass, and importing the verifier loads neither the production experiment module nor any forecast module.

### Task 5: Formal run, independent audit, and visual readout

**Files:**
- Create: `results/23_hbv_multilead_joint_uncertainty/g3_state_domain_consistent_process_noise_switch_v01/`
- Create: `results/23_hbv_multilead_joint_uncertainty/g3_state_domain_consistent_process_noise_switch_v01_independent_verification_v01/`
- Create: `docs/plans/2026-08-03-id23-state-domain-consistent-process-noise-switch-closure.md`

**Interfaces:**
- Consumes: passing focused tests and the frozen config.
- Produces: one scientifically classified result with complete evidence paths, or a stopped zero-projection/test/verification failure with no scientific conclusion.

- [ ] **Step 1: Run the complete focused regression set before the formal experiment.**

Run:

```powershell
$env:PYTHONPATH=(Resolve-Path 'src').Path
python -m pytest test/test_hbv_state_domain_consistent_process_noise_switch.py test/test_hbv_state_domain_consistent_process_noise_switch_runner.py test/test_hbv_state_domain_consistent_process_noise_switch_verifier.py test/test_hbv_three_stage_switching_validation.py test/test_hbv_joint_uncertainty_imm.py -q
```

Expected: all selected tests pass; otherwise stop.

- [ ] **Step 2: Confirm both final output paths are absent and run the formal experiment once.**

Run:

```powershell
$env:PYTHONPATH=(Resolve-Path 'src').Path
python src/hbv_multilead_joint_uncertainty/scripts/run_g3_state_domain_consistent_process_noise_switch.py
```

Expected: the atomic result directory appears only after zero truth projection, finite evidence, probability normalization, and image decoding pass.

- [ ] **Step 3: Run the independent verifier once.**

Run:

```powershell
$env:PYTHONPATH=(Resolve-Path 'src').Path
python src/hbv_multilead_joint_uncertainty/scripts/verify_g3_state_domain_consistent_process_noise_switch.py
```

Expected: `independent_verification_status` is `passed`; otherwise stop without a scientific conclusion.

- [ ] **Step 4: Visually inspect both result PNGs at original resolution and check final worktree scope.**

Require readable Chinese labels, correct switch boundaries, non-overlapping annotations, and no misleading forecast or real-basin language. Confirm no pre-existing file was cleaned, staged, committed, deleted, or overwritten.

- [ ] **Step 5: Write the closure with conclusion first and exact evidence boundaries.**

Report the three directed-transition success counts, response fractions, exact intervals, median and maximum response starts, zero-projection audit, test count, independent maximum reconstruction difference, and complete evidence paths. State explicitly that the result concerns a warm-wet synthetic HBV condition with lower-groundwater-only process noise, not general process noise, forecast skill, WALRUS, or real basins.

## Self-Review

- Spec coverage: the plan fixes parameters, changes only process-noise level, preserves continuous state, prohibits forecasts, requires zero truth projection, freezes the response rule prospectively, saves plots, and requires independent verification.
- Placeholder scan: no `TBD`, `TODO`, unspecified error handling, or deferred implementation remains.
- Type consistency: the module signatures, runner artifacts, verifier inputs, experiment ID, response window, event count, and result paths are consistent across all tasks.
- Dirty-worktree protection: all changes are new experiment-specific files and isolated result directories; no existing registry, source, test, or result file is modified.
