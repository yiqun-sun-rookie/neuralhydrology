# CAMELS-US parFC Path-Postcollapse Design90 03B Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prepare, hash-freeze, and technically preflight one 90-basin, design-seed-only C-versus-P configuration without starting any of its 360 tasks.

**Architecture:** Preserve the completed 03B mechanism runner, verifier, configuration, outputs, and logs byte-for-byte. Add scale-specific registration, execution, and independent-verification entry points that reuse the frozen 03B numerical helpers but derive counts from exactly 90 basins, seeds 0 and 1, and two arms. Generate a new task table, one 180-task fifteen-state initial-moment manifest, one full replacement preregistration, one configuration, one run manifest, and one preflight evidence file; stop before execution.

**Tech Stack:** Python 3.11.5, NumPy 1.26.4, pandas, pytest, SHA-256, HBV-lite, modified unscented filtering, and the existing pairwise-path-postcollapse interacting multiple-model implementation.

## Global Constraints

- The only writable repository is `G:\wt\camels-rising`; `G:\github\pycharm\projects\neuralhydrology` remains read-only.
- Preserve the dirty worktree and every existing result, log, configuration, and evidence file; do not commit, push, delete, clean, overwrite, or modify old evidence.
- Keep the completed 03B mechanism implementation files byte-identical so its frozen artifact chain remains rerunnable from the recorded source state.
- Use exactly the 90 basins in `docs/plans/2026-08-10-camels-parfc-state-interaction-design90-basins-v01.csv` and exactly design seeds `0,1`.
- Register exactly 180 source basin-seed tasks and 360 planned C/P tasks. Do not use seeds `2,3`, run 90 or 531 basins, or freeze a validation version 02 configuration.
- Change only scale relative to the passed 03B mechanism comparison: C is full interaction plus conservative `parFC` mapping; P is nine source-to-target paths observed separately and collapsed after observation with the same conservative mapping.
- Keep parameters, forcing, truth, seven 180-day stages, transition probabilities, process noise, observation noise, initial conditions, event rule, scoring slice `180:1260`, and ordinary-float recursive probabilities unchanged.
- Replace the obsolete direct-versus-nested absolute-difference stop with the final 03B contract: authoritative reconstruction is bitwise exact, every destination/global mixture passes the registered high-precision bound, and direct-versus-nested differences are reported only as diagnostics.
- A new result root and four new logs must be registered and absent. This turn may create only preparation artifacts; execution remains HOLD until a later explicit GO.
- No task includes a Git commit because commit authorization was not granted.

---

### Task 1: Seal the completed 03B mechanism evidence

**Files:**
- Create mechanically: `docs/plans/2026-08-11-camels-parfc-transition-path-mechanism10-03b-evidence-v01.json`
- Test: `test/test_camels_parameter_path_design90_registration.py`

**Interfaces:**
- Consumes: the frozen 03B config, runner summary, 20 probability files, verification task table, verification summary, and four logs.
- Produces: one immutable parent evidence record with the 25-file result collection hash `6d1e275c3d9d8f8b3a338311c8b7f734162b16d98343eacc3fbda1c253fd6327`, config hash `90f2a19e6f45a78fca08debe697166faac6046029ea4f6d677358de58b07132e`, verification-summary hash `8ad2ea45a1b2a6c2178d17e324b16e9e64bd12d521669958ab4f0d6e80d35d03`, and both passed continuation indicators.

- [ ] **Step 1: Write a failing evidence-builder test**

```python
def test_mechanism_evidence_requires_verified_go(tmp_path):
    summary = {"verification_status": "passed", "mechanism_gate_status": "HOLD"}
    with pytest.raises(ValueError, match="mechanism gate"):
        build_mechanism_evidence(summary=summary, result_entries=[], logs=[])
```

- [ ] **Step 2: Implement strict parent-evidence construction**

`build_mechanism_evidence` must require 20 tasks, 10 tasks per arm, `verification_status == "passed"`, `mechanism_gate_status == "GO"`, both registered scientific indicators true, the exact configuration hash, 25 sorted result entries in `relative_path,bytes,sha256` form, two zero-byte error logs, and no reference to seeds 2 or 3. It must record the non-uniform paired directions: severe days `9/1/0`, mean negative log probability `7/0/3`, and Brier score `6/0/4` for improved/equal/worse.

- [ ] **Step 3: Recompute rather than copy every digest**

Read all result files and logs, rebuild the newline-joined collection hash, and reject any mismatch before exclusively creating the evidence JSON.

---

### Task 2: Add an isolated 90-basin runner

**Files:**
- Create: `src/camels_switch_confirmation/run_parameter_path_design90.py`
- Create: `test/test_camels_parameter_path_design90.py`

**Interfaces:**
- Consumes: a registered Design90 config, its independently supplied SHA-256, 180 source C tasks, and a 180-row fifteen-state initial-moment manifest.
- Produces when separately authorized later: exactly 180 C and 180 P probability files plus arm task tables and a root summary.

- [ ] **Step 1: Write count and refusal tests**

```python
def test_design90_task_contract_accepts_exact_cross_product(case):
    verified = verify_parameter_path_design90(case.root, case.config, case.sha256)
    assert len(verified.task_table) == 180
    assert set(verified.task_table.seed) == {0, 1}
    assert len(build_work(verified)) == 360


@pytest.mark.parametrize("bad_count", [179, 181])
def test_design90_task_contract_rejects_wrong_count(case, bad_count):
    case.rewrite_task_count(bad_count)
    with pytest.raises(ValueError, match="180"):
        verify_parameter_path_design90(case.root, case.config, case.sha256)
```

Also reject duplicate basin-seed keys, any seed outside `{0,1}`, fewer or more than 90 basin identifiers, a basin list/task-table cross-product mismatch, a five-state initial manifest, changed source bytes or hashes, a changed runtime, a pre-existing output or log, and an output nested under any source or prior evidence root.

- [ ] **Step 2: Reuse frozen numerical helpers without modifying them**

Import runtime, file-hash, raw-input, source-content, parameter-row, initial-moment, output-isolation, work-construction, and `_run_one` helpers from the frozen 03B modules. Define new constants only in the Design90 module:

```python
CONFIGURATION_STATUS = "design90_exploratory_design_seeds_not_validation"
SOURCE_TASK_COUNT = 180
ARM_COUNT = 2
PLANNED_TASK_COUNT = 360
```

- [ ] **Step 3: Write scale-correct summaries and fail-fast execution**

The root summary must derive source, arm, planned, submitted, success, cancelled, and unsubmitted counts from the verified table and execution record. It must never contain hard-coded `10` or `20` task counts. Create output directories exclusively and use the existing first-failure scheduler with the registered worker count.

- [ ] **Step 4: Prove the frozen mechanism files did not change**

The regression test must assert SHA-256 values `72a9965e441f7c9168bff681b6661c8901772e4d7d3b39ad15edeca57904f6b5` for the mechanism runner and `6480c402b0bfa9b831713fda2681bc8eb5e0e52359b37cf51125e64ccfe668f1` for the mechanism verifier.

---

### Task 3: Add an independent 90-basin verifier and fixed gates

**Files:**
- Create: `src/camels_switch_confirmation/verify_parameter_path_design90.py`
- Create: `test/test_camels_parameter_path_design90_verifier.py`

**Interfaces:**
- Consumes: 360 completed probability files, 180 registered source files, the frozen configuration, and the initial-moment manifest.
- Produces when separately authorized later: `task_metrics.csv`, `event_metrics.csv`, `direction_summary.csv`, `paired_task_summary.csv`, and `verification_summary.json` in one atomic verification directory.

- [ ] **Step 1: Write pure gate tests before implementing the verifier**

```python
def test_design90_gate_requires_every_registered_condition():
    metrics = passing_gate_fixture()
    assert evaluate_design90_gates(metrics)["overall_status"] == "GO"
    for name in evaluate_design90_gates(metrics)["conditions"]:
        changed = failing_copy_for_condition(metrics, name)
        assert evaluate_design90_gates(changed)["overall_status"] == "HOLD"
```

- [ ] **Step 2: Independently validate all 360 files**

Reuse the frozen verifier's probability, event, truth-label, path-array, authoritative reconstruction, and high-precision mixture-audit helpers. Locally generalize task records to 180 per arm and reject any missing, extra, duplicate, failed, clipped, non-finite, non-normalized, or cross-arm-inconsistent task. Require source C probabilities and stable logs to reproduce within `1e-12`, with all six source event decisions identical.

- [ ] **Step 3: Compute the complete registered metrics**

For each arm, compute 194,400 equal-weight scoring days, 1,080 events, six direction counts, multiclass Brier score, arithmetic mean/median/99th/99.9th/maximum stable true-candidate negative log probability, counts below true probability `0.01`, counts above negative log probability `100`, exact-zero ordinary true probabilities, and 180 paired task directions for event count, Brier score, and stable negative log probability.

- [ ] **Step 4: Encode the ten immutable continuation conditions**

Require: 360/360 tasks and independent checks; P event count strictly above C with C exactly `706/1080`; P overall pass rate at least `0.65`; all six P direction rates at least `0.50`; no direction loses more than `9/180` versus C; P Brier no greater than C and `2/3`; P mean stable negative log probability no greater than C and `ln(3)`; P true-probability-below-0.01 days no more than `1,944`; P severe days exactly zero; and P exact-zero ordinary true-probability days exactly zero.

- [ ] **Step 5: Keep direct/nested diagnostics non-blocking**

Record direct-versus-nested absolute, relative, and floating-point-spacing maxima. Stop only if authoritative reconstruction is not bitwise exact or any registered high-precision destination/global ratio exceeds `1`.

---

### Task 4: Register and freeze the 90-basin preparation artifacts

**Files:**
- Create: `src/camels_switch_confirmation/register_parameter_path_design90.py`
- Create mechanically: `docs/plans/2026-08-11-camels-parfc-transition-path-03b-design90-tasks-v01.csv`
- Create mechanically: `docs/plans/2026-08-11-camels-parfc-transition-path-03b-design90-initial-moment-manifest-v01.npz`
- Create: `docs/plans/2026-08-11-camels-parfc-transition-path-03b-design90-prereg-v01.md`
- Create mechanically: `src/camels_switch_confirmation/configs/camels_parfc_transition_path_03b_design90.json`
- Create mechanically: `docs/plans/2026-08-11-camels-parfc-transition-path-03b-design90-run-manifest-v01.json`
- Create mechanically: `docs/plans/2026-08-11-camels-parfc-transition-path-03b-design90-preflight-evidence-v01.json`

**Interfaces:**
- Consumes: the fixed 90-basin list, its 1,260-day coverage table, 184-row raw-input manifest, calibrated parameter and precheck tables, completed prior Design90 arm-C files, completed 03B mechanism evidence, and final implementation/test hashes.
- Produces: experiment `CAMELS_PARFC_TRANSITION_PATH_03B_DESIGN90`, output root `results/23_camels_switch_confirmation/camels_parfc_transition_path_03b_design90_s01_20260811_local`, and four same-stem run/verification logs under `tmp/`.

- [ ] **Step 1: Generate the 180-row source task table deterministically**

Follow basin-list order and seed order `0,1`. Each row must identify arm C and register the completed state-interaction Design90 C file's relative path, byte count, and SHA-256. Require that embedded basin, seed, method, conservative mapping, filter settings, truth, and 1,260-day shapes match before writing.

- [ ] **Step 2: Generate fifteen-state initial moments independently**

For every task, save probabilities `(180,3)`, states `(180,3,15)`, and covariances `(180,3,15,15)` plus exact axis metadata and Unicode basin identifiers. Construct the moments with an explicit independent NumPy route, compare every value bitwise with the production initializer, and refuse to write on any mismatch.

- [ ] **Step 3: Write a full replacement preregistration**

Do not modify the 2026-08-10 preregistration. The new document must record the passed mechanism evidence, the non-uniform ten-task result, all fixed scientific settings, the 360-task scale, the final high-precision numerical contract, all ten continuation conditions, and claim boundaries.

- [ ] **Step 4: Freeze one config and one run manifest**

Register all source/input/parent-evidence/implementation/test/runtime hashes. The run manifest must record status `registered_not_run_awaiting_separate_user_go`, 360 tasks, four workers, exact output/log paths, and exact runner/verifier commands whose configuration hash is read from the manifest at execution time.

- [ ] **Step 5: Run configuration-only preflight**

Require 90 basins, 180 source keys, shapes `(180,3)`, `(180,3,15)`, `(180,3,15,15)`, 184 raw inputs, all implementation hashes, CPython 3.11.5/NumPy 1.26.4 runtime semantics, absent output/logs, unchanged 03B/03/03A evidence, and no matching Python process. Save the passed checks in the preflight evidence JSON.

---

### Task 5: Verify preparation and stop before execution

**Files:**
- Test: `test/test_camels_parameter_path_design90_registration.py`
- Test: `test/test_camels_parameter_path_design90.py`
- Test: `test/test_camels_parameter_path_design90_verifier.py`
- Test unchanged: `test/test_camels_parameter_path_mechanism.py`
- Test unchanged: `test/test_camels_parameter_path_mechanism_verifier.py`
- Test unchanged: `test/test_camels_switch_confirmation.py`
- Test unchanged: `test/test_hbv_joint_uncertainty_imm.py`
- Test unchanged: `test/test_hbv_parameter_state_mapping.py`

**Interfaces:**
- Consumes: all newly frozen preparation artifacts.
- Produces: a technical GO/HOLD decision for configuration readiness only.

- [ ] **Step 1: Run syntax checks and all eight related test files**

```powershell
$env:PYTHONPATH=(Resolve-Path 'src').Path
& 'C:\Users\yiqun\anaconda3\python.exe' -m pytest -q `
  test\test_camels_parameter_path_design90_registration.py `
  test\test_camels_parameter_path_design90.py `
  test\test_camels_parameter_path_design90_verifier.py `
  test\test_camels_parameter_path_mechanism.py `
  test\test_camels_parameter_path_mechanism_verifier.py `
  test\test_camels_switch_confirmation.py `
  test\test_hbv_joint_uncertainty_imm.py `
  test\test_hbv_parameter_state_mapping.py
```

- [ ] **Step 2: Recompute every frozen digest and run the runner's read-only verifier**

The verifier must return 180 source tasks and an absent new output root without creating it.

- [ ] **Step 3: Confirm execution remains unstarted**

Require zero new probability files, absent runner/verification outputs, absent four logs, and zero matching Python processes. Do not run either command in the run manifest.

---

## Self-Review

- Specification coverage: exact scale, design-only seeds, C/P one-factor comparison, parent mechanism evidence, fifteen-state initial moments, runtime/hash freeze, numerical-gate correction, ten scientific gates, output isolation, and no-run boundary all map to explicit tasks.
- Placeholder scan: no implementation or decision placeholder remains; the future command obtains its exact configuration digest from the frozen run manifest rather than using an editable token.
- Type consistency: runner, verifier, task table, initial manifest, and summaries all use 180 source tasks, two arms, 360 tasks, 15 states, and six events per source task.
- Execution handoff: the user selected inline continuation. This task executes preparation inline and stops before any 90-basin run; delegation was not requested.
