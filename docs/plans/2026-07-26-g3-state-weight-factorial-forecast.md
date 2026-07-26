# State-Weight Factorial Forecast Diagnostic Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build, preregister, run, and independently verify a two-by-two forecast diagnostic that separates the effect of final candidate weights from the effect of assimilation-period state interaction.

**Architecture:** Add one isolated scientific module that replays only the primary three-candidate family from sealed inputs under full state interaction and no state interaction. Each replay captures daily probabilities, terminal candidate state distributions, and candidate forecasts; a pure compositor crosses candidate forecasts with either set of final weights. A new runner validates sealed inputs, packages raw evidence and statistics, and refuses to overwrite or alter protected artifacts.

**Tech Stack:** Python 3, NumPy, pytest, existing HBV-lite candidate-bank and evidence-packaging utilities, Git.

---

### Task 1: Freeze the pure two-by-two compositor contract

**Files:**
- Create: `test/test_hbv_state_weight_factorial_diagnostic.py`
- Create: `src/hbv_multilead_joint_uncertainty/state_weight_factorial_diagnostic.py`

**Step 1: Write failing tests**

Add tests that require:

- candidate forecasts shaped `[lead, candidate]`;
- final weights shaped `[candidate]`, finite, nonnegative, and summing to one within `1e-12`;
- four exact combinations named `full_states_full_weights`, `full_states_none_weights`, `none_states_full_weights`, and `none_states_none_weights`;
- an exact prediction-scale nonadditive term;
- input arrays remain unchanged;
- malformed shapes and invalid probabilities raise `ValueError`.

**Step 2: Run the focused tests and confirm failure**

Run:

```powershell
$env:PYTHONIOENCODING='utf-8'
$env:PYTHONPATH='src'
pytest test/test_hbv_state_weight_factorial_diagnostic.py -q
```

Expected: collection or import failure because the new module does not exist.

**Step 3: Implement the minimal pure compositor**

Create:

```python
def combine_candidate_forecasts(
    candidate_forecasts: np.ndarray,
    final_probabilities: np.ndarray,
) -> np.ndarray:
    ...


def state_weight_factorial_forecasts(
    full_candidate_forecasts: np.ndarray,
    none_candidate_forecasts: np.ndarray,
    full_final_probabilities: np.ndarray,
    none_final_probabilities: np.ndarray,
) -> dict[str, np.ndarray]:
    ...
```

The compositor must not run filters, read truth, or mutate inputs.

**Step 4: Run the focused tests**

Expected: all Task 1 tests pass.

**Step 5: Commit**

```powershell
git add -- test/test_hbv_state_weight_factorial_diagnostic.py src/hbv_multilead_joint_uncertainty/state_weight_factorial_diagnostic.py
git commit -m "feat(id23): add state-weight forecast compositor"
```

### Task 2: Capture terminal candidate state distributions from one assimilation

**Files:**
- Modify: `src/hbv_multilead_joint_uncertainty/state_weight_factorial_diagnostic.py`
- Modify: `test/test_hbv_state_weight_factorial_diagnostic.py`

**Step 1: Write failing tests**

Require an immutable result object containing:

```python
@dataclass(frozen=True)
class TerminalAssimilationForecast:
    daily_probabilities: np.ndarray
    final_candidate_states: np.ndarray
    final_candidate_covariances: np.ndarray
    candidate_forecasts: np.ndarray
    combined_forecast: np.ndarray
```

Tests must verify:

- one bank is built and assimilated once;
- `interaction_mode` is either `full` or `none`;
- every assimilation day assigns forcing before the observation update;
- terminal state and full covariance are copied before forecasting;
- forecast probabilities remain frozen and candidate state mixing is absent;
- the returned combined forecast equals candidate forecasts multiplied by the final probabilities within `1e-12`;
- caller inputs and terminal snapshots are not mutated by forecasting.

**Step 2: Run tests and confirm failure**

Expected: missing result type and assimilation function.

**Step 3: Implement**

Add:

```python
def assimilate_terminal_forecast(
    candidates,
    initial_states,
    initial_covariance,
    active_forcing,
    observations,
    assimilation_days,
    leads,
    observation_standard_deviation,
    factor_transition_stay_probability,
    interaction_mode,
) -> TerminalAssimilationForecast:
    ...
```

Use `build_method_bank()` and `forecast_from_posterior()` without changing either historical function.

**Step 4: Run tests**

Expected: Task 1 and Task 2 tests pass.

**Step 5: Commit**

```powershell
git add -- test/test_hbv_state_weight_factorial_diagnostic.py src/hbv_multilead_joint_uncertainty/state_weight_factorial_diagnostic.py
git commit -m "feat(id23): capture terminal candidate forecasts"
```

### Task 3: Build the sealed-input driver

**Files:**
- Modify: `src/hbv_multilead_joint_uncertainty/state_weight_factorial_diagnostic.py`
- Modify: `test/test_hbv_state_weight_factorial_diagnostic.py`

**Step 1: Write failing tests**

Use a small synthetic sealed-input mapping and a monkeypatched terminal-assimilation function. Require:

- exactly one `full` and one `none` assimilation for every block and truth trial;
- stable axes `[block, truth, lead, candidate]` for candidate forecasts;
- stable axes `[block, truth, assimilation_day, candidate]` for probabilities;
- terminal states `[block, truth, candidate, state]`;
- terminal covariances `[block, truth, candidate, state, state]`;
- four forecast arrays `[block, truth, lead]`;
- truth labels determine the final true-candidate index rather than assuming truth-loop order;
- source arrays remain unchanged.

**Step 2: Run tests and confirm failure**

Expected: missing driver.

**Step 3: Implement**

Add:

```python
def compare_state_weight_factorial(
    sealed_inputs,
    candidates,
    observation_standard_deviation,
    factor_transition_stay_probability,
) -> dict:
    ...
```

The driver reads forcing, observations, initial states, covariances, labels, and truth forecasts from the supplied sealed mapping. It does not generate truth or write files.

**Step 4: Run tests**

Expected: all new module tests pass.

**Step 5: Commit**

```powershell
git add -- test/test_hbv_state_weight_factorial_diagnostic.py src/hbv_multilead_joint_uncertainty/state_weight_factorial_diagnostic.py
git commit -m "feat(id23): add sealed state-weight driver"
```

### Task 4: Add paired inference and practical-equivalence classification

**Files:**
- Modify: `src/hbv_multilead_joint_uncertainty/state_weight_factorial_diagnostic.py`
- Modify: `test/test_hbv_state_weight_factorial_diagnostic.py`

**Step 1: Write failing tests**

Construct deterministic block-level arrays covering:

- practically equivalent;
- materially improves;
- materially harms;
- unresolved;
- the four weight/state comparisons;
- complete full-minus-none comparison;
- wrong-candidate displacement ratio and wrong-minus-true squared-error difference.

Verify that the practical-equivalence interval is:

```python
(-0.0199 * baseline_mse, 0.0201 * baseline_mse)
```

and classification order is equivalence first, then material improvement or harm, then unresolved.

**Step 2: Run tests and confirm failure**

Expected: missing statistics and classifier functions.

**Step 3: Implement**

Add:

```python
def classify_effect_interval(
    lower: float,
    upper: float,
    equivalence_lower: float,
    equivalence_upper: float,
) -> str:
    ...


def summarize_state_weight_factorial(
    driver_output: dict,
    bootstrap_replicates: int,
    bootstrap_seed: int,
    minimum_rmse_fraction: float,
) -> dict:
    ...
```

Resample matched blocks only. Use the same resampled block indices for all leads and comparisons.

**Step 4: Run tests**

Expected: all new module tests pass.

**Step 5: Commit**

```powershell
git add -- test/test_hbv_state_weight_factorial_diagnostic.py src/hbv_multilead_joint_uncertainty/state_weight_factorial_diagnostic.py
git commit -m "feat(id23): add factorial mechanism inference"
```

### Task 5: Add the sealed evidence runner and package contract

**Files:**
- Create: `src/hbv_multilead_joint_uncertainty/scripts/run_g3_state_weight_factorial.py`
- Modify: `test/test_hbv_state_weight_factorial_diagnostic.py`

**Step 1: Write failing runner tests**

Require the runner to:

- refuse an existing final, incomplete, or preregistration path before reading config;
- require output directory name to equal the experiment identifier;
- validate exact sealed-input and sealed-forecast-reference checksums;
- reject output/protected-path overlap before preregistration;
- validate parameter, process-noise, observation-noise, candidate-order, block, lead, and assimilation-day identities against the sealed input;
- cross-check truth, observations, both daily-probability arrays, no-interaction candidate forecasts, and both historical diagonal combinations against the sealed forecast reference;
- internally reconstruct the full-interaction combination from new full-interaction candidate forecasts and final weights;
- save all raw arrays, block-level statistics, snapshots, hashes, and checksums;
- refuse overwrite on a second call.

**Step 2: Run tests and confirm failure**

Expected: runner module is missing.

**Step 3: Implement the runner**

Reuse the existing atomic JSON, environment, protected hashing, resource preflight, source snapshot, and atomic directory-finalization helpers. Do not modify historical runners.

**Step 4: Run focused tests**

Expected: all new tests pass.

**Step 5: Commit**

```powershell
git add -- test/test_hbv_state_weight_factorial_diagnostic.py src/hbv_multilead_joint_uncertainty/scripts/run_g3_state_weight_factorial.py
git commit -m "feat(id23): package state-weight evidence"
```

### Task 6: Freeze the formal configuration and registry row

**Files:**
- Create: `src/hbv_multilead_joint_uncertainty/configs/g3_state_weight_factorial_param_switch_v01.json`
- Modify: `src/hbv_multilead_joint_uncertainty/configs/g3_experiment_registry.csv`
- Modify: `test/test_hbv_state_weight_factorial_diagnostic.py`

**Step 1: Write failing config-contract tests**

Require:

- experiment identifier `g3_state_weight_factorial_param_switch_v01`;
- design document path;
- sealed ideal-input evidence and sealed highest-posterior evidence paths plus SHA-256 values;
- forecast contract with identity transition, fixed final probabilities, and no forecast state mixing;
- exactly two assimilation modes and four frozen combination names;
- 20,000 matched-block bootstrap replicates, seed `3310757`, and minimum meaningful root-mean-square-error fraction `0.01`;
- all previous G3 result directories, configurations, design documents, implementation plans, and closures protected.

**Step 2: Run tests and confirm failure**

Expected: missing config and registry row.

**Step 3: Add config and registry row**

Set status to `preregistered`; do not edit the config after formal execution begins.

**Step 4: Run focused and relevant regression tests**

Run:

```powershell
$env:PYTHONIOENCODING='utf-8'
$env:PYTHONPATH='src'
pytest test/test_hbv_state_weight_factorial_diagnostic.py -q
pytest test/test_hbv_*forecast*.py test/test_hbv_interaction_value_comparison.py -q
```

Expected: all pass with only the existing unknown-pytest-config warning.

**Step 5: Commit the preregistration**

```powershell
git add -- src/hbv_multilead_joint_uncertainty/configs/g3_state_weight_factorial_param_switch_v01.json src/hbv_multilead_joint_uncertainty/configs/g3_experiment_registry.csv test/test_hbv_state_weight_factorial_diagnostic.py
git commit -m "phase(id23): preregister state-weight diagnostic"
```

### Task 7: Verify the clean implementation before formal execution

**Files:**
- No source changes.

**Step 1: Confirm clean Git state and exact commit**

Run:

```powershell
git status --short
git rev-parse HEAD
```

Expected: clean status and the preregistration commit.

**Step 2: Verify copied ignored inputs**

Copy only the sealed input directories into this isolated worktree, then verify their declared SHA-256 values. Do not link the output directory to the dirty main worktree.

**Step 3: Run the complete relevant suite**

Run the frozen relevant test list plus the new test file.

Expected: all pass.

**Step 4: Run an independent pre-execution method review**

Review:

- no future truth or discharge enters any combination;
- candidate forecasts and weights align by the same candidate order;
- each full/none assimilation runs once;
- no parameter-state transplant occurs;
- practical-equivalence direction and bounds are correct;
- output paths cannot overlap protected inputs.

Any important finding blocks execution.

### Task 8: Execute and seal the formal diagnostic

**Files:**
- Create ignored result package: `results/23_hbv_multilead_joint_uncertainty/g3_state_weight_factorial_param_switch_v01/`
- Create ignored external preregistration: `results/23_hbv_multilead_joint_uncertainty/g3_state_weight_factorial_param_switch_v01.preregistered.json`

**Step 1: Run exactly once**

Run:

```powershell
$env:PYTHONIOENCODING='utf-8'
$env:PYTHONPATH='src'
python -m hbv_multilead_joint_uncertainty.scripts.run_g3_state_weight_factorial `
  --repo-root . `
  --config src/hbv_multilead_joint_uncertainty/configs/g3_state_weight_factorial_param_switch_v01.json `
  --output-dir results/23_hbv_multilead_joint_uncertainty/g3_state_weight_factorial_param_switch_v01
```

Expected: one completed package, no incomplete directory, integrity status `passed`.

**Step 2: Verify package checksums and protected hashes**

Expected: every manifest entry matches and every protected artifact is unchanged.

**Step 3: Independently recompute from `evidence.npz`**

Do not call the project summarizer. Recompute:

- all four combinations;
- all squared errors;
- all block-level contrasts;
- bootstrap intervals and classifications;
- wrong-candidate displacement ratios;
- replay and diagonal reconstruction gates.

Expected: exact or declared machine-precision agreement.

**Step 4: Request independent method/code review**

Critical or important findings block closure.

### Task 9: Close, verify, and integrate

**Files:**
- Create: `docs/plans/2026-07-26-g3-state-weight-factorial-closure.md`
- Modify: `src/hbv_multilead_joint_uncertainty/configs/g3_experiment_registry.csv`

**Step 1: Write evidence-proportional closure**

Separate:

- observed results;
- supported mechanism interpretation;
- unresolved mechanisms;
- one-scenario scope limit.

**Step 2: Mark registry completed**

Record the exact result path and concise verdict without editing the frozen config.

**Step 3: Run final verification**

Run all relevant tests, package checksums, protected hashes, source-snapshot comparison, and `git diff --check`.

**Step 4: Commit closure**

```powershell
git add -- docs/plans/2026-07-26-g3-state-weight-factorial-closure.md src/hbv_multilead_joint_uncertainty/configs/g3_experiment_registry.csv
git commit -m "phase(id23): close state-weight diagnostic"
```

**Step 5: Integrate without touching the dirty main worktree**

Create a clean temporary integration worktree, merge this feature branch into the current `migration/reorg-v1` commit, rerun the relevant suite with copied ignored inputs, then advance the main branch reference only after confirming the dirty main worktree status and tracked-content digest are unchanged.
