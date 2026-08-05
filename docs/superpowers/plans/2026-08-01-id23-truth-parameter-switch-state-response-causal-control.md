# ID23 True-Parameter Switch State-Response Causal Control Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and independently verify a state-only matched causal control that isolates how each sealed true-parameter switch changes all fifteen synthetic truth states over the next thirty days.

**Architecture:** The production calculation will branch from each sealed pre-switch truth state and propagate the old-parameter and new-parameter branches with identical forcing and identical saved process perturbations through the independent reference truth path. A separate verifier will reconstruct the same branches with the candidate-filter adapter equations without importing the production module. Results will be published only into one new experiment directory after physical, provenance, reconstruction, and no-observation/no-forecast checks pass.

**Tech Stack:** Python 3.11, NumPy, Matplotlib, pytest, JSON/CSV/NPZ evidence files, SHA-256 provenance.

## Global Constraints

- Experiment identifier: `g3_truth_parameter_switch_state_response_causal_control_v01`.
- Population: 8 sealed blocks × 3 truth trials × 2 switch boundaries = 48 matched events; 30 daily response leads; all 15 states.
- Switch boundaries are between days 180–181 and 360–361; stored zero-based future indices are 180 and 360.
- Both branches start from the exact same saved fifteen-state vector at the day before the switch.
- Both branches use the exact same future meteorological forcing and saved fifteen-state process-perturbation vector at every lead.
- The only changed factor is continuing the old true parameter vector versus using the new true parameter vector for all thirty response days.
- Do not reset or remap the initial state outside the normal parameter-specific physical projection already present in the sealed generator; record that projection adjustment explicitly.
- Do not read `observed_discharge`, do not execute observation updates, and do not import or evaluate forecast modules.
- Primary propagation uses `hbv_multilead_joint_uncertainty.synthetic_truth.advance_reference_state` and `project_reference_state`.
- Independent verification uses `hbv_joint_uncertainty.hbv_adapter.advance_state` and `hbv_joint_uncertainty.preflight.project_hbv_state`; it must not import the production causal-control module or runner.
- Frozen truth evidence SHA-256: `77f84d793f18a72972e5af5f2ac4ed767645471e37da31c612ab995ecf4bbf67`.
- Frozen state-scale evidence SHA-256: `22f1b99ee0cf537e1aa7c9b414662c0b390510f2dc0d6b07bf538dd6dda33a04`.
- Frozen primary reference source hashes: `synthetic_truth.py` = `f2cffdf30115ec3a7a3530314cab155325d646b46f5b5271628568601f269f8d`; `hbv_lite_numpy.py` = `0a18663e3c3306dfe59d34a628aae1854b296e041d414a9ba15733e59100ffdd`.
- Frozen independent verifier source hashes: `hbv_adapter.py` = `4955ba523012ec75adced08cf0ce8b21b712dcd8ef9d02cc35adc21c53654437`; `preflight.py` = `95aa7e73e8889b3e28e3f45b5c5ad47d16ef8e108ba6eefd4bd955c87f348d88`.
- State standardization uses the fifteen frozen `truth_standard_deviation` values from the state-scale evidence, without refitting.
- Physical checks require finite states, nonnegative states, soil moisture not above the active `parFC`, meltwater not above `parCWH × SNOWPACK`, exact zero routing-memory perturbations, and exact newest-first routing-memory shifts within tolerance `1e-12`.
- The new-parameter branch must reconstruct the corresponding thirty saved truth states with maximum absolute error at most `1e-12`.
- Clean-truth decision gate: any nonzero pre-transition projection adjustment when the saved pre-switch state is interpreted under the new parameters makes the current generator `not suitable as a clean general state-accuracy truth condition`; it remains a labelled abrupt parameter-switch stress test and requires a separate fixed-parameter state-jump recovery experiment.
- If generation, source hashing, physical checks, truth reconstruction, checksums, or independent verification fails, stop without a scientific conclusion.
- Never clean, restore, stage, commit, delete, or overwrite user files. Commit steps from the generic planning template are intentionally omitted because the user explicitly forbids staging and committing.

---

### Task 1: Freeze the experiment contract and registry entry

**Files:**
- Create: `src/hbv_multilead_joint_uncertainty/configs/g3_truth_parameter_switch_state_response_causal_control_v01.json`
- Modify: `src/hbv_multilead_joint_uncertainty/configs/g3_experiment_registry.csv` by appending exactly one new row
- Create: `test/test_hbv_truth_parameter_switch_state_response_runner.py`

**Interfaces:**
- Consumes: the hashes, dimensions, decision gate, and source paths in Global Constraints.
- Produces: `DEFAULT_CONFIG`, `DEFAULT_OUTPUT`, `_validate_config(config: dict) -> None`, and `_require_unused_output(path: Path) -> None` in the runner used by later tasks.

- [ ] **Step 1: Write failing frozen-contract tests**

```python
def test_config_freezes_state_only_matched_control():
    config = json.loads(Path(DEFAULT_CONFIG).read_text(encoding="utf-8"))
    _validate_config(config)
    assert config["status"] == "frozen_before_run"
    assert config["response_days"] == 30
    assert config["switch_boundaries_zero_based"] == [180, 360]
    assert config["only_changed_factor"] == (
        "true parameter vector used for matched state propagation: continue old versus switch to new"
    )
    assert config["observed_discharge_read"] is False
    assert config["forecast_executed"] is False
    assert config["state_reset_at_switch"] is False


def test_existing_output_is_rejected(tmp_path):
    existing = tmp_path / "existing"
    existing.mkdir()
    with pytest.raises(FileExistsError, match="already exists"):
        _require_unused_output(existing)
```

- [ ] **Step 2: Run the tests and confirm they fail before files exist**

Run: `python -m pytest -q test/test_hbv_truth_parameter_switch_state_response_runner.py`

Expected: collection or import failure because the new runner/config does not exist.

- [ ] **Step 3: Add the immutable JSON config**

The config must contain the exact population, source hashes, required source shapes, branch names, state groups, physical checks, result file contract, and clean-truth decision gate from Global Constraints. It must set `status` to `frozen_before_run` and output to `results/23_hbv_multilead_joint_uncertainty/g3_truth_parameter_switch_state_response_causal_control_v01`.

- [ ] **Step 4: Add the runner contract validation and append one registry row**

```python
EXPERIMENT_ID = "g3_truth_parameter_switch_state_response_causal_control_v01"
BRANCH_NAMES = (
    "continue_old_true_parameters",
    "switch_to_new_true_parameters",
)


def _require_unused_output(output_dir: Path) -> None:
    if output_dir.exists():
        raise FileExistsError(f"output directory already exists: {output_dir}")
```

The registry row type is `controlled synthetic truth-state causal audit`; status is `frozen_before_run`; checkpoint is `not applicable`; paper name is `G3 true-parameter switch state-response causal control`.

- [ ] **Step 5: Run the frozen-contract tests**

Run: `python -m pytest -q test/test_hbv_truth_parameter_switch_state_response_runner.py`

Expected: PASS.

### Task 2: Implement matched thirty-day state propagation and summaries

**Files:**
- Create: `src/hbv_multilead_joint_uncertainty/truth_parameter_switch_state_response.py`
- Create: `test/test_hbv_truth_parameter_switch_state_response.py`

**Interfaces:**
- Consumes: explicit parameter mappings, one finite fifteen-state initial vector, forcing `(30, 3)`, process perturbations `(30, 15)`, and fifteen positive frozen state scales.
- Produces: `propagate_matched_parameter_branches(...) -> dict[str, np.ndarray]`, `build_switch_events(...) -> dict[str, np.ndarray]`, and `summarize_state_response(...) -> dict[str, np.ndarray | str | int]`.

- [ ] **Step 1: Write failing unit tests for the only-changed-factor contract**

```python
def test_matched_branches_share_initial_state_forcing_and_perturbations():
    result = propagate_matched_parameter_branches(
        initial_state=initial_state,
        forcing=forcing,
        process_perturbations=perturbations,
        old_parameters=old_parameters,
        new_parameters=new_parameters,
    )
    assert result["branch_states"].shape == (2, 30, 15)
    np.testing.assert_array_equal(result["initial_states"], np.stack((initial_state, initial_state)))
    np.testing.assert_array_equal(result["shared_forcing"], forcing)
    np.testing.assert_array_equal(result["shared_process_perturbations"], perturbations)


def test_identical_parameters_produce_zero_response():
    result = propagate_matched_parameter_branches(
        initial_state, forcing, perturbations, old_parameters, old_parameters
    )
    np.testing.assert_allclose(result["branch_state_difference"], 0.0, atol=0.0)


def test_summary_includes_all_fifteen_states_and_two_groups():
    summary = summarize_state_response(differences, scales, event_transition_indices)
    assert summary["standardized_response"].shape[-1] == 15
    assert summary["group_root_mean_square_standardized_response"].shape[-1] == 2
    assert summary["per_state_peak_lead"].shape == (15,)
```

- [ ] **Step 2: Run the unit tests and confirm they fail**

Run: `python -m pytest -q test/test_hbv_truth_parameter_switch_state_response.py`

Expected: import failure because the core module does not exist.

- [ ] **Step 3: Implement strict validation and one-event propagation**

```python
def propagate_matched_parameter_branches(
    initial_state: np.ndarray,
    forcing: np.ndarray,
    process_perturbations: np.ndarray,
    old_parameters: Mapping[str, float],
    new_parameters: Mapping[str, float],
) -> dict[str, np.ndarray]:
    branch_states = np.empty((2, len(forcing), 15), dtype=np.float64)
    pretransition_adjustments = np.empty_like(branch_states)
    posttransition_adjustments = np.empty_like(branch_states)
    for branch_index, parameters in enumerate((old_parameters, new_parameters)):
        state = np.asarray(initial_state, dtype=np.float64).copy()
        for lead, (daily_forcing, perturbation) in enumerate(zip(forcing, process_perturbations)):
            physical_before = project_reference_state(state, parameters)
            pretransition_adjustments[branch_index, lead] = physical_before - state
            deterministic = advance_reference_state(state, *daily_forcing, parameters)
            unprojected = deterministic + perturbation
            state = project_reference_state(unprojected, parameters)
            posttransition_adjustments[branch_index, lead] = state - unprojected
            branch_states[branch_index, lead] = state
    return {
        "initial_states": np.stack((initial_state, initial_state)),
        "shared_forcing": forcing.copy(),
        "shared_process_perturbations": process_perturbations.copy(),
        "branch_states": branch_states,
        "branch_state_difference": branch_states[1] - branch_states[0],
        "pretransition_projection_adjustments": pretransition_adjustments,
        "posttransition_projection_adjustments": posttransition_adjustments,
    }
```

- [ ] **Step 4: Implement event assembly, physical checks, and summaries**

The event builder must iterate block, truth trial, and boundary in that order; extract `truth_states[..., boundary - 1, :]`, forcing at `warmup_days + boundary : + 30`, and saved perturbations at `boundary : + 30`. The summary must retain signed/raw/standardized response arrays; root-mean-square response curves by state, transition, and state group; first-day response; maximum response; first lead of that maximum; and pre-transition new-domain projection adjustments.

- [ ] **Step 5: Run the core tests**

Run: `python -m pytest -q test/test_hbv_truth_parameter_switch_state_response.py`

Expected: PASS.

### Task 3: Build fail-closed formal runner, tables, and figures

**Files:**
- Complete: `src/hbv_multilead_joint_uncertainty/scripts/run_g3_truth_parameter_switch_state_response_causal_control.py`
- Create: `src/hbv_multilead_joint_uncertainty/truth_parameter_switch_state_response_plotting.py`
- Extend: `test/test_hbv_truth_parameter_switch_state_response_runner.py`

**Interfaces:**
- Consumes: frozen config, only the required named arrays from both evidence archives, and Task 2 functions.
- Produces: `config_snapshot.json`, `environment.json`, `evidence.npz`, `per_state_summary.csv`, `transition_state_summary.csv`, `response_curves.csv`, `summary.json`, three PNG figures, and `checksums.json` in one new result directory.

- [ ] **Step 1: Add failing runner tests for forbidden inputs and exact source shapes**

```python
def test_runner_imports_no_forecast_module():
    completed = subprocess.run(
        [sys.executable, "-c", IMPORT_CHECK],
        check=True,
        capture_output=True,
        text=True,
        env={**os.environ, "PYTHONPATH": "src"},
    )
    assert completed.stdout.strip() == "False"


def test_source_loader_does_not_request_observed_discharge(monkeypatch):
    requested = []
    arrays = _source_arrays(fake_truth_path, fake_scale_path, config, on_read=requested.append)
    assert "observed_discharge" not in requested
```

- [ ] **Step 2: Implement named-array loading and preflight hashes**

The runner must read only `forcing_blocks`, `warmup_days`, `truth_states`, `truth_process_perturbations`, `truth_parameter_indices`, `parameter_ids`, and `parameter_vectors` from truth evidence, plus `truth_standard_deviation` and `state_names` from state-scale evidence. Verify both evidence hashes and all four frozen model-source hashes before calculation.

- [ ] **Step 3: Implement physical/reconstruction gates and decision**

The new branch must match the sealed future truth states to tolerance. Any failed physical check or reconstruction mismatch must raise before publication. The decision is:

```python
if pretransition_new_domain_projection_event_count > 0:
    decision = "requires_separate_fixed_parameter_state_jump_recovery_experiment"
else:
    decision = "suitable_as_clean_parameter_switch_truth_condition_for_state_accuracy"
```

The summary must state that the numerical response is HBV synthetic truth-generator evidence only and contains no assimilation-method or forecast comparison.

- [ ] **Step 4: Implement accessible state-response figures**

- `per_state_standardized_response.png`: fifteen small multiples, three directed true-parameter transitions, x-axis leads 1–30, y-axis root-mean-square standardized new-minus-old response magnitude.
- `state_group_standardized_response.png`: hydrologic-store and routing-memory group response curves, including a pooled curve.
- `initial_new_parameter_domain_projection.png`: event-by-state heat map of absolute initial new-domain projection adjustment standardized by frozen state scale.

Use the color-blind-safe blue/orange/green palette and state explicitly that curves are causal branch differences rather than prediction errors.

- [ ] **Step 5: Implement exclusive staging and publish without cleanup**

Reject an existing final output directory. Create one unique `.incomplete.<uuid>` sibling, write all artifacts there, compute checksums, and rename it to the final directory only after every production gate passes. If execution fails, leave the incomplete directory intact; do not delete it.

- [ ] **Step 6: Run core and runner tests**

Run: `python -m pytest -q test/test_hbv_truth_parameter_switch_state_response.py test/test_hbv_truth_parameter_switch_state_response_runner.py`

Expected: PASS.

### Task 4: Implement an independent adapter-path verifier

**Files:**
- Create: `src/hbv_multilead_joint_uncertainty/scripts/verify_g3_truth_parameter_switch_state_response_causal_control.py`
- Create: `test/test_hbv_truth_parameter_switch_state_response_verifier.py`

**Interfaces:**
- Consumes: published config snapshot, truth/scale evidence, output evidence and tables.
- Produces: `independent_verification.json` only if that file does not already exist; exits nonzero when any check fails.

- [ ] **Step 1: Write failing independence tests**

```python
def test_verifier_imports_neither_production_control_nor_forecast_modules():
    assert subprocess.run(
        [sys.executable, "-c", IMPORT_CHECK],
        check=True,
        capture_output=True,
        text=True,
        env={**os.environ, "PYTHONPATH": "src"},
    ).stdout.strip().splitlines() == ["False", "False"]


def test_maximum_difference_rejects_shape_mismatch():
    assert _maximum_difference(np.ones(1), np.ones((1, 1))) == float("inf")
```

- [ ] **Step 2: Run verifier tests and confirm failure**

Run: `python -m pytest -q test/test_hbv_truth_parameter_switch_state_response_verifier.py`

Expected: import failure because the verifier does not exist.

- [ ] **Step 3: Implement independent daily propagation**

For every event and branch, call `project_hbv_state` before transition, `advance_state` for the daily deterministic step, add the shared saved process perturbation, and call `project_hbv_state` again. Recompute every saved state/difference/standardized response/summary array without importing Task 2 or the production runner.

- [ ] **Step 4: Verify artifacts, tables, figures, checksums, and forbidden scope**

The report must verify all numeric arrays within `1e-12`, exact labels and shapes, truth reconstruction, physical checks, decision text, CSV values, result checksums, PNG decoding, and that `observed_discharge_read` and `forecast_executed` remain false.

- [ ] **Step 5: Run verifier tests**

Run: `python -m pytest -q test/test_hbv_truth_parameter_switch_state_response_verifier.py`

Expected: PASS.

### Task 5: Execute, audit, and close the experiment

**Files:**
- Create at runtime: `results/23_hbv_multilead_joint_uncertainty/g3_truth_parameter_switch_state_response_causal_control_v01/`
- Create: `docs/plans/2026-08-01-id23-truth-parameter-switch-state-response-causal-control-closure.md`
- Modify: the one new registry row in `src/hbv_multilead_joint_uncertainty/configs/g3_experiment_registry.csv` from `frozen_before_run` to the verified final status.

**Interfaces:**
- Consumes: all Tasks 1–4 deliverables.
- Produces: a complete, independently verified evidence package and a bounded scientific decision.

- [ ] **Step 1: Run the focused tests**

Run: `python -m pytest -q test/test_hbv_truth_parameter_switch_state_response.py test/test_hbv_truth_parameter_switch_state_response_runner.py test/test_hbv_truth_parameter_switch_state_response_verifier.py`

Expected: all tests PASS.

- [ ] **Step 2: Recheck hashes, config, worktree, and absent output directory**

Run read-only SHA-256 checks for both evidence files and all four model-source files; inspect `git status --short`; require the final result directory not to exist.

- [ ] **Step 3: Run the formal state-only causal control**

Run: `python src/hbv_multilead_joint_uncertainty/scripts/run_g3_truth_parameter_switch_state_response_causal_control.py`

Expected: a complete-pending-verification package in the isolated final directory; no forecast or observation-update output.

- [ ] **Step 4: Run independent verification**

Run: `python src/hbv_multilead_joint_uncertainty/scripts/verify_g3_truth_parameter_switch_state_response_causal_control.py`

Expected: `independent_verification.json` with status `passed` and overall maximum numeric difference at most `1e-12`.

- [ ] **Step 5: Visually inspect all figures and independently recompute decisive counts**

Open all PNG files at original resolution. Separately recompute the count of pre-transition new-domain projection events, per-state first-day response, thirty-day maxima and peak leads, and both state-group curves directly from `evidence.npz`.

- [ ] **Step 6: Write closure and update only the new registry row**

The closure must lead with the decision, list all per-state and group metrics, document the hidden parameter-domain projection mechanism, give every evidence path and hash, and state that the finding applies only to this HBV synthetic truth generator. Update the registry row only after independent verification passes.

- [ ] **Step 7: Run the final completion audit**

Check every objective requirement against the config, result files, verifier report, focused tests, figure inspection, and closure. Do not mark the goal complete if any item is missing or only indirectly supported.

## Self-Review

- Spec coverage: every requirement maps to a task—single-factor matched branches (Task 2), thirty days/all fifteen states (Tasks 2–3), frozen hashes/config/output (Tasks 1 and 5), no observations/forecast/state reset (Tasks 1–4), physical checks and fail-closed publication (Task 3), independent recomputation (Task 4), per-state/group reports and final suitability decision (Tasks 3 and 5).
- Placeholder scan: every implementation and test step is concrete and fully specified.
- Type consistency: the runner and verifier both consume the same explicit branch names, event order, `(events, branches, 30, 15)` state shape, frozen scale vector, and output labels.
- Execution mode: inline execution in the current session because the user did not authorize subagent delegation and the referenced execution sub-skills are not available in this session.
