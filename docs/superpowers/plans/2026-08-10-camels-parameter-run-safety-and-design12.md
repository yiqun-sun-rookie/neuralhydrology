# CAMELS Parameter Run Safety and Design12 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add registered-input verification and fail-fast execution, then run one three-arm, 12-basin, design-seed-only diagnostic that separates state-interaction effects from conservative soil-capacity state-mapping effects.

**Architecture:** Keep generic input-integrity checks and bounded fail-fast scheduling in two focused modules. Add a registered parameter-interaction runner that verifies one immutable exploratory configuration, creates one output root, executes three paired arms, and writes partial evidence with a nonzero exit code on the first observed task failure. Reuse the existing parameter-switch task implementation after changing its output destination from a global tag to an explicit probability directory.

**Tech Stack:** Python 3.11, NumPy, pandas, `concurrent.futures`, pytest, SHA-256, existing HBV-lite and interacting multiple-model implementations.

## Global Constraints

- The only writable code host is `G:\wt\camels-rising` on branch `codex/camels-rising-half-recal`.
- `G:\github\pycharm\projects\neuralhydrology` is read-only.
- Preserve every pre-existing modification, untracked file, and result; do not clean the worktree.
- Do not commit, push, delete, overwrite an existing output, or modify the main repository.
- Use only design seeds `{0,1}`. Do not use validation seeds `{2,3}`.
- Do not create or label any version-02 frozen configuration and do not run all 531 basins.
- The three arms must share identical truth, observations, forcing, candidates, noise settings, switch schedule, and event rules.
- The run is exploratory mechanism evidence only; it cannot establish 531-basin candidate identification, state accuracy, forecast value, or real-observation assimilation value.
- A first task failure stops new submissions. Already-running tasks may finish safely because Python 3.11 has no public safe process-termination API.
- No task in this plan includes a Git commit step because commits are outside the authorized scope.

---

### Task 1: Registered input and implementation integrity gate

**Files:**
- Create: `src/camels_switch_confirmation/run_integrity.py`
- Create: `test/test_camels_switch_run_integrity.py`

**Interfaces:**
- Consumes: repository root, configuration path, caller-supplied configuration SHA-256, expected output root.
- Produces: `VerifiedParameterRun` and `verify_parameter_run_config(repo_root, config_path, expected_config_sha256) -> VerifiedParameterRun`.

- [ ] **Step 1: Write focused failure tests**

```python
def test_verify_parameter_run_config_rejects_configuration_hash_change(tmp_path):
    config_path, expected_hash = build_registered_fixture(tmp_path)
    config_path.write_text(config_path.read_text() + "\n", encoding="utf-8")
    with pytest.raises(ValueError, match="configuration SHA-256 changed"):
        verify_parameter_run_config(tmp_path, config_path, expected_hash)


def test_verify_parameter_run_config_rejects_raw_input_hash_change(tmp_path):
    config_path, expected_hash = build_registered_fixture(tmp_path)
    (tmp_path / "data" / "forcing.txt").write_text("changed", encoding="utf-8")
    with pytest.raises(ValueError, match="input file SHA-256 changed"):
        verify_parameter_run_config(tmp_path, config_path, expected_hash)


def test_verify_parameter_run_config_rejects_reserved_validation_seed(tmp_path):
    config_path, expected_hash = build_registered_fixture(tmp_path, seeds=[0, 2])
    with pytest.raises(ValueError, match="design seeds must be exactly \[0, 1\]"):
        verify_parameter_run_config(tmp_path, config_path, expected_hash)
```

- [ ] **Step 2: Run the integrity tests and confirm they fail for the missing interface**

Run:

```powershell
$env:PYTHONPATH=(Resolve-Path 'src').Path
& 'C:\Users\yiqun\anaconda3\python.exe' -m pytest -q test\test_camels_switch_run_integrity.py
```

Expected: collection or import failure naming `verify_parameter_run_config`.

- [ ] **Step 3: Implement the configuration contract and SHA-256 verification**

```python
@dataclass(frozen=True)
class VerifiedParameterRun:
    experiment_id: str
    configuration_status: str
    config_path: Path
    config_sha256: str
    basin_ids: tuple[str, ...]
    data_root: Path
    output_root: Path
    arms: tuple[dict, ...]
    registered_hashes: dict[str, str | int]


def sha256_file(path: str | Path) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()
```

`verify_parameter_run_config` must reject absolute or parent-traversing registered paths; verify the configuration hash before parsing; require status `registered_exploratory_design_not_validation_frozen`; require design seeds exactly `[0,1]` and reserved seeds exactly `[2,3]`; verify the parameter table, first-stage precheck table, basin list, coverage table, raw-input manifest, and every listed implementation file; verify every raw file byte count and SHA-256; require one Maurer forcing file and one United States Geological Survey streamflow file per selected basin plus the shared topography table and forcing-loader source; require exactly 1260 finite forcing days from `1989-10-01` through `1993-03-13`; and require the three registered arms below in this order:

```python
EXPECTED_ARMS = (
    {"arm_id": "A", "interaction_mode": "parameter_grouped",
     "parameter_state_mapping": "legacy_projection"},
    {"arm_id": "B", "interaction_mode": "full",
     "parameter_state_mapping": "legacy_projection"},
    {"arm_id": "C", "interaction_mode": "full",
     "parameter_state_mapping": "conservative_parfc"},
)
```

- [ ] **Step 4: Add success, missing-column, duplicate-basin, coverage, implementation-drift, and output-root tests**

```python
def test_verify_parameter_run_config_returns_exact_registered_identity(tmp_path):
    config_path, expected_hash = build_registered_fixture(tmp_path)
    verified = verify_parameter_run_config(tmp_path, config_path, expected_hash)
    assert verified.basin_ids == ("01022500",)
    assert [arm["arm_id"] for arm in verified.arms] == ["A", "B", "C"]
    assert verified.configuration_status == (
        "registered_exploratory_design_not_validation_frozen"
    )
```

- [ ] **Step 5: Run the integrity tests**

Expected: every test in `test_camels_switch_run_integrity.py` passes.

---

### Task 2: Bounded fail-fast process execution

**Files:**
- Create: `src/camels_switch_confirmation/batch_control.py`
- Create: `test/test_camels_switch_batch_control.py`

**Interfaces:**
- Consumes: ordered work items, a picklable worker, task-key callback, positive maximum worker count, optional executor factory for tests.
- Produces: `BatchExecution(records, execution_status, first_failure, n_planned, n_submitted, n_cancelled_before_start, n_not_submitted_after_failure, n_completed_after_stop)`.

- [ ] **Step 1: Write the returned-failure and complete-success tests**

```python
def test_execute_fail_fast_stops_submitting_after_returned_failure():
    execution = execute_fail_fast(
        work=[("b1", 0), ("b2", 0), ("b3", 0)],
        worker=worker_that_fails_b1,
        task_key=lambda item: item,
        max_workers=1,
        executor_factory=ImmediateExecutor,
    )
    assert execution.execution_status == "failed_early"
    assert execution.n_submitted == 1
    assert execution.n_not_submitted_after_failure == 2


def test_execute_fail_fast_success_path_runs_every_task():
    execution = execute_fail_fast(
        work=[("b1", 0), ("b2", 0)],
        worker=successful_worker,
        task_key=lambda item: item,
        max_workers=2,
        executor_factory=ImmediateExecutor,
    )
    assert execution.execution_status == "complete"
    assert [record["run_status"] for record in execution.records] == [
        "success", "success"
    ]
```

- [ ] **Step 2: Run the scheduler tests and confirm the interface is absent**

Run the new file alone. Expected: import failure for `execute_fail_fast`.

- [ ] **Step 3: Implement bounded submission using `wait(..., FIRST_COMPLETED)`**

```python
@dataclass(frozen=True)
class BatchExecution:
    records: list[dict]
    execution_status: str
    first_failure: dict | None
    n_planned: int
    n_submitted: int
    n_cancelled_before_start: int
    n_not_submitted_after_failure: int
    n_completed_after_stop: int
```

Submit no more than `max_workers` initially. Process every future returned in one completion batch in original task-index order. Treat returned failure records, future exceptions, submission exceptions, and malformed status fields as failures. If any failure appears, do not replenish the queue, cancel futures that have not begun, call `shutdown(wait=True, cancel_futures=True)`, collect already-running completions with `completed_after_stop=True`, and append explicit records for cancelled and never-submitted tasks.

- [ ] **Step 4: Add exception, cancellation, and already-running-task tests**

```python
def test_execute_fail_fast_converts_future_exception_to_failure():
    execution = execute_fail_fast(...)
    assert execution.first_failure["run_status"] == "failed"
    assert "RuntimeError" in execution.first_failure["error_message"]


def test_execute_fail_fast_collects_running_completion_after_stop():
    execution = execute_fail_fast(...)
    late = [r for r in execution.records if r.get("completed_after_stop")]
    assert len(late) == 1
```

- [ ] **Step 5: Run all scheduler tests**

Expected: complete success with deterministic task indexes and counts.

---

### Task 3: Integrate atomic task output and partial-run evidence

**Files:**
- Modify: `src/camels_switch_confirmation/g2_switch_confirmation.py`
- Create: `src/camels_switch_confirmation/registered_parameter_interaction.py`
- Modify: `test/test_camels_switch_confirmation.py`
- Create: `test/test_camels_registered_parameter_interaction.py`

**Interfaces:**
- Consumes: `VerifiedParameterRun`, `execute_fail_fast`, existing `_run_one` parameter-switch task.
- Produces: one registered output root with `arms/A`, `arms/B`, `arms/C`; per-arm event tables and summaries; root `runner_summary.json`; exit code 1 with partial evidence on failure.

- [ ] **Step 1: Write failing tests for atomic files and zero-success evidence**

```python
def test_atomic_save_npz_refuses_existing_target(tmp_path):
    target = tmp_path / "task.npz"
    target.write_bytes(b"existing")
    with pytest.raises(FileExistsError):
        _atomic_save_npz(target, values=np.array([1.0]))


def test_write_arm_evidence_handles_zero_success_records(tmp_path):
    summary = write_arm_evidence(
        tmp_path,
        records=[{"basin_id": "01022500", "seed": 0,
                  "run_status": "failed", "error_message": "boom"}],
        execution=failed_execution(),
        g1_frame=minimal_g1_frame(),
    )
    assert summary["scientific_aggregation_status"] == (
        "not_evaluated_incomplete_execution"
    )
    assert (tmp_path / "g2_basin_verdicts.csv").read_text().startswith(
        "basin_id,events_total,events_passed,verdict"
    )
```

- [ ] **Step 2: Change `_run_one` to receive an explicit probability directory**

Replace the tuple's final global output tag with `probability_directory` and `arm_id`. Save every compressed task file through `_atomic_save_npz`; record `arm_id` in the task record and probability metadata. The legacy command-line path must construct its existing directory explicitly, so historical defaults retain their behavior.

- [ ] **Step 3: Implement the registered three-arm runner**

```python
def run_registered_parameter_design(
    config_path: str | Path,
    expected_config_sha256: str,
    workers: int,
) -> dict:
    verified = verify_parameter_run_config(
        _REPO_ROOT, config_path, expected_config_sha256
    )
    output = prepare_output_root(verified.output_root)
    for arm in verified.arms:
        execution = execute_fail_fast(...)
        write_arm_evidence(...)
        if execution.execution_status != "complete":
            write_root_summary(..., status="failed_early")
            raise RuntimeError("parameter design stopped after first task failure")
    return write_root_summary(..., status="complete")
```

The root and every arm directory must be created with `exist_ok=False`. Preflight all hashes before creating the output root. A failed arm must not start later arms. An incomplete run must set `basin_verdict_status` and `scientific_aggregation_status` to `not_evaluated_incomplete_execution`, omit pass-rate and significance claims, write the first failure and scheduler counts, and return nonzero.

- [ ] **Step 4: Make the legacy G2 command use the same fail-fast scheduler**

Replace its all-at-once `ProcessPoolExecutor` loop with `execute_fail_fast`. Preserve the legacy default options. On a complete run return 0; on any failure write partial event, verdict, and summary files and return 1.

- [ ] **Step 5: Run task-specific tests**

Run:

```powershell
$env:PYTHONPATH=(Resolve-Path 'src').Path
& 'C:\Users\yiqun\anaconda3\python.exe' -m pytest -q `
  test\test_camels_switch_batch_control.py `
  test\test_camels_switch_run_integrity.py `
  test\test_camels_registered_parameter_interaction.py `
  test\test_camels_switch_confirmation.py `
  test\test_hbv_parameter_state_mapping.py `
  test\test_hbv_joint_uncertainty_imm.py
```

Expected: all listed tests pass. Run `test/test_hbv_joint_uncertainty_preflight.py` separately and report its known missing external table fixture independently.

---

### Task 4: Register the 12-basin three-arm exploratory design

**Files:**
- Create: `docs/plans/2026-08-10-camels-parfc-state-interaction-design12-prereg-v01.md`
- Create: `docs/plans/2026-08-10-camels-parfc-state-interaction-registry-v01.csv`
- Create: `docs/plans/2026-08-10-camels-parfc-state-interaction-design12-basins-v01.csv`
- Create: `docs/plans/2026-08-10-camels-parfc-state-interaction-design12-input-manifest-v01.csv`
- Create: `docs/plans/2026-08-10-camels-parfc-state-interaction-design12-coverage-v01.csv`
- Create: `docs/plans/2026-08-10-camels-parfc-state-interaction-design12-run-manifest-v01.json`
- Create: `src/camels_switch_confirmation/configs/camels_parfc_state_interaction_design12_v01.json`

**Interfaces:**
- Consumes: final implementation hashes, existing parameter and precheck tables, exact 12-basin raw inputs.
- Produces: one SHA-256-identified exploratory configuration for `CAMELS_PARFC_STATE_INTERACTION_01_DESIGN12`.

- [ ] **Step 1: Recompute the mechanical selection without using existing switch outcomes**

Sort all 531 successful precheck rows by `(r_min, basin_id)`, split ranks `0:177`, `177:354`, and `354:531`, then split each group by whether initial soil water exceeds the actual bounded half-capacity candidate `fc_member2`. Within each of six cells choose the one-third and two-thirds internal ranks. Require the exact basin sequence:

```text
10244950,09210500,14154500,05408000,
03604000,02465493,04127918,01605500,
11266500,11481200,05488200,04015330
```

Require all 12 first-stage prechecks to be successful, feasible without truth clipping, and covered for 1260 days.

- [ ] **Step 2: Build and hash the exact input tables**

The raw-input manifest must contain 28 unique rows: two basin files for each of 12 basins plus topography, forcing-loader source, parameter table, and precheck table. The coverage table must record exactly 1260 days, start `1989-10-01`, end `1993-03-13`, finite precipitation, potential evapotranspiration, and mean temperature for every basin.

- [ ] **Step 3: Register the three arms and fixed scientific contract**

Fix candidates to center, half, and double bounded soil capacity; seven 180-day stages in the existing order; true lower-groundwater multiplicative lognormal standard deviation 0.02; filter lower-groundwater-only fixed covariance scale `3e-8`; observation-variance multiplier 1; transition diagonal 0.98; and the existing 30-day, five-consecutive-day event rule. Register arms A, B, and C exactly as Task 1 specifies.

- [ ] **Step 4: Register only a continuation gate**

The continuation gate is: all `72/72` tasks and independent checks pass; arm C has strictly more passed events than arm A; arm C's multiclass Brier score is no larger than arm A's; and arm C's mean true-candidate negative log probability is no larger than arm A's. State explicitly that this is not a scientific success threshold and cannot authorize validation seeds or a 531-basin run.

- [ ] **Step 5: Compute final hashes and run integrity preflight without starting workers**

Pass the final configuration path and its SHA-256 to `verify_parameter_run_config`. Expected: 12 basins, three arms, all registered files and implementation hashes verified, and no output directory created.

---

### Task 5: Execute and independently compare the design-seed diagnostic

**Files:**
- Create: `src/camels_switch_confirmation/verify_parameter_interaction_design.py`
- Create: `test/test_camels_parameter_interaction_verifier.py`
- Create only through the registered runner: `results/23_camels_switch_confirmation/camels_parfc_state_interaction_01_design12_s01_20260810_local/`

**Interfaces:**
- Consumes: completed three-arm output, registered configuration and hashes.
- Produces: independent integrity report, paired arm comparison, probability-quality metrics, and a continuation-gate result.

- [ ] **Step 1: Write verifier tests using synthetic miniature arm outputs**

```python
def test_verifier_rejects_cross_arm_truth_change(tmp_path):
    root = build_three_arm_fixture(tmp_path)
    replace_truth_value(root / "arms" / "B" / "probs" / "01022500_s0.npz")
    with pytest.raises(ValueError, match="truth_q differs across arms"):
        verify_design(root, config_path, config_sha256)


def test_verifier_recomputes_event_and_probability_metrics(tmp_path):
    report = verify_design(build_three_arm_fixture(tmp_path), ...)
    assert report["task_count"] == 6
    assert report["probability_sum_maximum_absolute_error"] <= 1e-12
```

- [ ] **Step 2: Implement independent verification**

Rehash the configuration and all registered inputs by a separate code path; require exactly 24 tasks per arm; require finite normalized probabilities; recompute all six event decisions per task; require cross-arm `truth_q`, observations, switch days, candidate parameters, process-noise settings, and observation-noise settings to be exactly equal; and reject any task or metadata mismatch.

- [ ] **Step 3: Run the registered design once**

Run the registered runner with design seeds `[0,1]`, the configuration SHA-256, and a conservative worker count. The output root must not exist before the command. Redirect standard output and standard error to new files under `tmp/`. If any stop condition fires, retain partial evidence and do not rerun with changed settings.

- [ ] **Step 4: Independently verify and compute paired comparisons**

Report arm A→B, B→C, and A→C changes for 144 events, 24 paired basin-seed tasks, all six directions, multiclass Brier score after day 180, and mean true-candidate negative log probability. Also require arm A probabilities and event decisions to match the registered old-method reference within the predeclared numerical tolerance; exact truth and observations remain mandatory.

- [ ] **Step 5: Apply the continuation gate and stop**

If the gate passes, recommend only a separately reviewed larger design-seed experiment. If it fails, hold the parameter line and diagnose the failed arm or metric. In both cases, do not freeze a configuration, use seeds `{2,3}`, or launch a 531-basin run.

