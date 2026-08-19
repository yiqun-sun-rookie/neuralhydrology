# CAMELS parFC Observation-Postcollapse Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Neither execution skill is installed in this session, so the primary agent will execute the same test-first checkpoints inline.

**Goal:** Add and evaluate a fixed-cost, one-step path-retaining multiple-model filter that delays source-to-destination hypothesis collapse until after the daily observation update.

**Architecture:** Keep the existing standard interacting multiple-model implementation unchanged as the baseline. Add a parallel estimator that expands three previous parameter candidates into nine source-to-destination branches, applies the existing conservative parFC moment conversion once on each cross-parameter branch, advances and updates every branch with the destination model, then collapses the nine posterior branches back to three destination-conditioned states. To isolate collapse timing, both methods use the same ordinary floating-point posterior probabilities as the next day's recursive weights; stable normalized log probabilities are saved only for scoring and audit. The public output remains one probability-weighted fifteen-state global posterior.

**Tech Stack:** Python 3.11, NumPy, pandas, pytest, existing modified unscented filters and CAMELS registered-run infrastructure.

## Global Constraints

- The only writable code host is `G:\wt\camels-rising`; the main repository is read-only.
- Preserve every existing tracked and untracked worktree change; do not clean, reset, delete, commit, or push.
- Use only design seeds 0 and 1. Do not use reserved validation seeds 2 and 3.
- Do not run all 531 basins.
- Do not change parameters, process noise, observation noise, transition probabilities, truth generation, stage order, or event thresholds.
- Do not add probability floors, likelihood temperatures, noise inflation, pruning thresholds, a recovery duration, or a learned transition model.
- Existing standard interacting multiple-model outputs must remain reproducible to absolute probability tolerance `1e-12`.
- A run stops on any hash mismatch, non-finite value, non-positive innovation variance, truth clipping, existing output, task failure, or independent-verification failure.
- Candidate identification, complete-state accuracy, forecast value, and real-observation value remain separate claims.

---

### Task 1: One-step path-retaining estimator

**Files:**
- Modify: `src/hbv_joint_uncertainty/imm.py`
- Modify: `test/test_hbv_joint_uncertainty_imm.py`

**Interfaces:**
- Consumes: `ModifiedUnscentedFilter`, `PairwiseMomentTransform`, a row-stochastic transition matrix, and initial mode probabilities.
- Produces: `PairwisePathMultipleModel.step(observation) -> PairwisePathStepResult`.
- `PairwisePathStepResult` exposes `prior_probabilities`, `posterior_probabilities`, `posterior_log_probabilities`, `branch_prior_log_probabilities`, `branch_posterior_log_probabilities`, `branch_results`, `destination_states`, `destination_covariances`, `combined_prior_observation`, `combined_state`, and `combined_covariance`.

- [ ] **Step 1: Add failing tests for exact branch weighting**

Add a two-model linear fixture and assert for every source `i` and destination `j`:

```python
expected_log_weight = (
    log(previous_ordinary_probability[i])
    + np.log(transition[i, j])
    + branch_result[i][j].log_likelihood
)
```

After global normalization, the four branch probabilities must sum to one and each destination probability must equal the sum of its incoming branch probabilities.

- [ ] **Step 2: Add failing tests for observation-before-collapse behavior**

Construct a low-capacity persistent source whose predicted observation matches the datum and a high-to-low incoming source whose mapped state produces a large mismatch. Assert that the low-to-low branch wins inside the low destination even when the high source has dominant previous mode probability. The existing observation-before-update interaction must remain unchanged as the baseline control.

- [ ] **Step 3: Add failing moment and stability tests**

Assert:

```python
np.testing.assert_allclose(
    direct_branch_global_state,
    result.combined_state,
    rtol=0.0,
    atol=1e-12,
)
np.testing.assert_allclose(
    direct_branch_global_covariance,
    result.combined_covariance,
    rtol=0.0,
    atol=1e-11,
)
```

Also assert single-candidate exact reduction, finite normalized destination probabilities, stable normalized log-probability output, symmetric destination covariances, and one cross-parameter transform call per active `i != j` branch. Add a two-step test proving that a posterior probability which underflows to ordinary zero has zero recursive source mass on the next step, exactly as in the baseline; the saved stable log value must not revive it.

- [ ] **Step 4: Run the new tests and record the expected import failures**

Run:

```powershell
$env:PYTHONPATH=(Resolve-Path 'src').Path
& 'C:\Users\yiqun\anaconda3\python.exe' -m pytest -q `
  test\test_hbv_joint_uncertainty_imm.py -k 'pairwise_path or postcollapse'
```

Expected result: failures because `PairwisePathMultipleModel` and `PairwisePathStepResult` do not exist.

- [ ] **Step 5: Implement stable branch expansion and posterior collapse**

Implement these exact operations:

```python
branch_log_prior[i, j] = log(self.probabilities[i]) + log_transition[i, j]
branch_log_posterior_unnormalized[i, j] = (
    branch_log_prior[i, j] + branch_results[i][j].log_likelihood
)
```

For `i == j`, copy the source moments. For `i != j`, invoke `pairwise_moment_transform(i, j, mean, covariance)` exactly once before constructing a temporary destination-filter clone. Normalize all active branch weights in log space. Collapse posterior moments by destination using posterior conditional branch weights, then calculate the global posterior both from the collapsed destinations and directly from branches and stop if they differ beyond the registered tolerances.

`self.probabilities` is authoritative for recursion. A zero ordinary probability produces a `-inf` branch prior on the next day. `posterior_log_probabilities` remains an audit/scoring output and is never used to reconstruct recursive mass. This deliberately matches the existing baseline and prevents numerical representation from becoming a second experimental factor.

- [ ] **Step 6: Run focused and legacy interaction tests**

Run:

```powershell
$env:PYTHONPATH=(Resolve-Path 'src').Path
& 'C:\Users\yiqun\anaconda3\python.exe' -m pytest -q `
  test\test_hbv_joint_uncertainty_imm.py
```

Expected result: all tests pass; all existing `InteractingMultipleModel` tests remain unchanged.

---

### Task 2: CAMELS parameter-switch integration

**Files:**
- Modify: `src/camels_switch_confirmation/g2_switch_confirmation.py`
- Modify: `test/test_camels_switch_confirmation.py`

**Interfaces:**
- Consumes: `interaction_mode="pairwise_path_postcollapse"` and `parameter_state_mapping="conservative_parfc"`.
- Produces: the same task-level `probabilities`, stable `log_probabilities`, truth arrays, event records, and unique fifteen-state global posterior contract as existing modes. For the new method it additionally saves every day's nine branch prior and posterior log weights, likelihoods, posterior states, posterior covariances, prior observations, innovation covariances, the three persistent source states/covariances before the step, the three destination states/covariances written back after the step, the unique global state/covariance, and the direct-versus-nested global first- and second-moment errors.

- [ ] **Step 1: Add failing contract tests**

Assert that the new interaction mode rejects legacy projection, builds `PairwisePathMultipleModel`, retains exactly three persistent destination filters and nine daily branch updates, records `hypothesis_collapse_timing="after_observation"`, and records `recursive_probability_representation="ordinary_float"`. Assert the old modes still build `InteractingMultipleModel` and preserve their defaults.

- [ ] **Step 2: Add a deterministic two-day mapping-call test**

Use a two-model transition matrix and recorded transform callback. Assert the high-to-low branch is converted once on each distinct high-to-low hypothesis, while the low-to-low continuation branch is identity and is not reconverted.

- [ ] **Step 3: Implement the new build path**

Extend `validate_parameter_interaction_contract`, command-line choices, `_build_bank`, output metadata, and summary metadata. Accumulate and save the complete new-method branch and persistent-state audit arrays listed above in each task probability file. Require each day's saved persistent source moments to equal the previous day's saved destination moments, so the actual recursive state can be audited rather than only the within-day mixture algebra. Do not change the existing `full`, `parameter_grouped`, or `legacy_projection` execution paths.

- [ ] **Step 4: Run CAMELS and mapping regression tests**

Run:

```powershell
$env:PYTHONPATH=(Resolve-Path 'src').Path
& 'C:\Users\yiqun\anaconda3\python.exe' -m pytest -q `
  test\test_camels_switch_confirmation.py `
  test\test_hbv_parameter_state_mapping.py `
  test\test_hbv_joint_uncertainty_imm.py
```

Expected result: all tests pass.

---

### Task 3: Mechanism smoke and failure-selected replay

**Files:**
- Create: `src/camels_switch_confirmation/run_parameter_path_mechanism.py`
- Create: `src/camels_switch_confirmation/verify_parameter_path_mechanism.py`
- Create: `test/test_camels_parameter_path_mechanism.py`
- Create: `test/test_camels_parameter_path_mechanism_verifier.py`
- Create after Task 2 hashes are final: `src/camels_switch_confirmation/configs/camels_parfc_transition_path_03_mechanism10.json`
- Create after the configuration hash is final: `docs/plans/2026-08-10-camels-parfc-transition-path-mechanism10-run-manifest-v01.json`
- Create: `docs/plans/2026-08-10-camels-parfc-path-postcollapse-smoke-evidence-v01.json`
- Use without modifying: `docs/plans/2026-08-10-camels-parfc-overconfidence-diagnostic-tasks-v02.csv`

**Interfaces:**
- Consumes: exactly the ten rows in `docs/plans/2026-08-10-camels-parfc-overconfidence-diagnostic-tasks-v02.csv` and their registered source files.
- Produces: isolated development outputs under `results/23_camels_switch_confirmation/camels_parfc_transition_path_03_mechanism10_s01_20260810_local/{C,P}` plus one immutable mechanism evidence file; no validation conclusion.

- [ ] **Step 0: Add and test the exact mechanism runner**

The runner reads only the fixed configuration above and requires its expected SHA-256 as an independent command-line argument. Before creating output it verifies the configuration SHA-256, task-table SHA-256, exactly ten unique `(basin_id, seed)` pairs, seeds in `{0,1}`, each matching C source artifact, registered implementation hashes, fixed hydrologic/noise settings, and exact arms `C=(full, conservative_parfc)` and `P=(pairwise_path_postcollapse, conservative_parfc)`. It refuses an existing root, creates isolated `{C,P}/probs` directories, runs exactly 20 tasks through the fail-fast executor, and writes task records and a configuration-linked summary. Tests must cover a valid temporary fixture, incorrect configuration SHA-256, altered task hash, duplicate/missing pair, wrong seed, wrong arm, existing output, and first-task failure. The executable entry point is fixed as:

```powershell
$env:PYTHONPATH=(Resolve-Path 'src').Path
& 'C:\Users\yiqun\anaconda3\python.exe' -X utf8 -m `
  camels_switch_confirmation.run_parameter_path_mechanism `
  --config src/camels_switch_confirmation/configs/camels_parfc_transition_path_03_mechanism10.json `
  --expected-config-sha256 <the 64-hex value recorded in the run manifest> `
  --workers 4
```

- [ ] **Step 1: Run the exact twenty-task paired mechanism check once**

Run C and P for all ten registered `(basin_id, seed)` pairs through the single configuration-locked command. Fail-fast scheduling stops new submissions on any task failure. Require every C task's truth, observations, forcing, candidate vectors, ordinary probabilities, stable log probabilities, and six event decisions to match its registered parent task within `1e-12`.

- [ ] **Step 2: Verify every P mechanism artifact**

For every P task require 1,260 finite normalized probability rows, finite stable log probabilities, zero truth clipping, and inputs identical to its paired C task. The independent verifier must reconstruct candidate masses, each destination's first two moments, and the global first two moments from raw branch arrays; compare them with saved destination/global arrays; and verify that day `t+1` persistent source moments equal day `t` destination moments. Recompute the count of days with true-candidate negative log probability above 100. State maximum absolute errors must be at most `1e-12`; covariance maximum absolute errors must be at most `1e-11`. Report basin `05501000`, seed `1` separately as the known worst parent task, but do not use it as a gate for submitting the other nine pairs.

- [ ] **Step 3: Recompute the fixed ten-task aggregate**

This is an outcome-selected causal check. For each of the ten tasks use exactly array indices `180:1260` (calendar days 181--1260), select the saved stable normalized log probability at that day's true candidate, negate it, and concatenate all `10 × 1080 = 10,800` values with equal daily weight. Report the count strictly greater than `100`, the arithmetic mean over all 10,800 values, event decisions, and ordinary-probability zeros, but do not call it a representative performance result.

- [ ] **Step 4: Stop or continue**

Continue to the 90-basin paired experiment only if, over the exact 10,800-value aggregate, P has both (a) a strictly smaller count above 100 and (b) a strictly smaller arithmetic mean than C, without changing truth, observations, forcing, candidates, noise, or ordinary-probability recursion. The isolated runner command including the literal expected configuration SHA-256, implementation hashes, source-task-table hash, output hashes, and formulas must be written to `docs/plans/2026-08-10-camels-parfc-path-postcollapse-smoke-evidence-v01.json`. Otherwise retain the outputs, mark the method `HOLD`, and do not create a design90 run configuration.

---

### Task 4: Registered two-arm design90 comparison

**Files:**
- Modify: `src/camels_switch_confirmation/run_integrity.py`
- Modify: `src/camels_switch_confirmation/registered_parameter_interaction.py`
- Create: `src/camels_switch_confirmation/verify_parameter_path_postcollapse_design.py`
- Modify: `test/test_camels_switch_run_integrity.py`
- Modify: `test/test_camels_registered_parameter_interaction.py`
- Create: `test/test_camels_parameter_path_postcollapse_verifier.py`
- Create after implementation hashes are final: `src/camels_switch_confirmation/configs/camels_parfc_transition_path_03_design90.json`
- Create: `docs/plans/2026-08-10-camels-parfc-transition-path-design90-registry-v01.csv`
- Create: `docs/plans/2026-08-10-camels-parfc-transition-path-design90-run-manifest-v01.json`

**Interfaces:**
- Consumes: exactly the existing 90-basin list, 184-file raw-input manifest, design seeds `[0, 1]`, and two registered arms: `C=(full, conservative_parfc)` and `P=(pairwise_path_postcollapse, conservative_parfc)`.
- Produces: 360 paired tasks, 2,160 events, an independently reconstructed metric table, direction table, tail-risk table, and decision-gate report.

- [ ] **Step 1: Generalize the registered input gate without weakening old contracts**

Add an optional explicit `expected_arms` argument to `verify_parameter_run_config`; its default remains the exact historical A/B/C tuple. The new runner passes the exact C/P tuple. Add tests proving the default rejects C/P and the explicit C/P contract rejects every other order or mode.

- [ ] **Step 2: Add the complete two-arm verifier tests**

Build temporary 90-basin-shaped fixtures with reduced day arrays and test: complete success; missing task; cross-arm truth difference; incorrect mode metadata; probability non-normalization; stable-log mismatch; baseline probability drift; nonzero truth clipping; output-exists refusal; and each registered decision gate.

- [ ] **Step 3: Implement independent verification**

The verifier must read every probability file, never trust runner metric summaries, and recompute events, Brier score, stable negative log probability, daily quantiles, counts below probability 0.01, counts above negative log probability 100, exact zero probabilities, six directions, and 180 paired task changes. For every P task it must also read the saved nine-branch weights, states, covariances, likelihoods, prior observations, and innovation covariances; verify shapes, finiteness, symmetry, strictly positive scalar innovation variance, branch normalization and destination mass; and independently reconstruct direct and nested global moments for every day.

- [ ] **Step 4: Run all registration and verifier tests**

Run:

```powershell
$env:PYTHONPATH=(Resolve-Path 'src').Path
& 'C:\Users\yiqun\anaconda3\python.exe' -m pytest -q `
  test\test_camels_switch_run_integrity.py `
  test\test_camels_registered_parameter_interaction.py `
  test\test_camels_parameter_path_postcollapse_verifier.py
```

- [ ] **Step 5: Freeze the design-seed configuration and hashes**

After all code and tests are final, write one configuration snapshot, one registry row, one run manifest, and one new output root. Rehash every implementation file and all registered inputs. Do not edit registered implementation files after computing the configuration hash.

- [ ] **Step 6: Execute once and verify independently**

Run 90 basins × 2 design seeds × 2 methods. On completion, run the independent verifier once into a new `verification` directory. Preserve standard output, empty or nonempty standard error, command, exit code, configuration hash, and artifact hashes.

---

### Task 5: Evidence and decision

**Files:**
- Create: `docs/plans/2026-08-10-camels-parfc-transition-path-03-design90-evidence.json`

**Interfaces:**
- Consumes: independently verified task, event, direction, and tail-risk tables.
- Produces: one evidence record and a `GO`, `HOLD`, or `NO-GO` recommendation bounded to the reused 90-basin design set.

- [ ] **Step 1: Apply the pre-registered gates without modification**

All gates in `docs/plans/2026-08-10-camels-parfc-transition-path-design90-prereg-v01.md` are conjunctive. Do not tune thresholds after observing the result.

- [ ] **Step 2: Record claims and limits**

If every gate passes, recommend only user review for a future frozen validation design. Do not create that configuration or use seeds 2 and 3. If any gate fails, keep validation `HOLD`, identify the failed metric, and do not search a path-retention duration in this experiment.

- [ ] **Step 3: Run final tests and hash evidence**

Run all touched tests, `git diff --check`, and hash the configuration, logs, raw results, verification tables, and evidence file. Do not commit or push.

## Self-Review

- The plan changes one scientific factor: hypothesis-collapse timing.
- The conservative state mapping, process and observation noise, transition matrix, truth, candidates, seeds, event rule, basin selection, and forcing remain fixed.
- The baseline standard interacting multiple-model implementation is retained and tested unchanged.
- The new method uses fixed nine-branch daily complexity and introduces no retention-length or pruning hyperparameter.
- The main output remains one probability-weighted fifteen-state global posterior.
- Both methods recurse from ordinary floating-point probabilities; stable log probabilities are scoring outputs only, so collapse timing remains the sole experimental factor.
- Complete per-day nine-branch audit arrays make the new method's probability and moment contracts independently reconstructable without trusting runner summaries.
- No step authorizes validation seeds, all 531 basins, state-accuracy claims, forecast claims, commit, or push.
