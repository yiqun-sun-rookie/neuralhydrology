# Historical Multiscale Formal Version 09 Action Resources Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add evidence-bound resource estimators and lock-scoped execution guards for formal target construction, model training, and formal prediction while leaving every formal authorization disabled.

**Architecture:** Freeze action-specific host and accelerator working-set formulas in the version-09 protocol. Build strict, hash-bound estimates from that protocol, validate them again at launch, and keep the operating-system lease for the complete callback lifetime. Add a streaming formal target writer so the first future formal action has a bounded implementation; training and prediction receive reusable guarded library entry points without implementing or starting either workload.

**Tech Stack:** Python 3, NumPy, pandas, PyTorch CUDA memory inspection, pytest, JSON and SHA-256 protocol binding.

## Global Constraints

- Use only Maurer forcing and the frozen 27 static attributes for model inputs.
- Preserve 531 basins, the sealed evaluation period, eight seeds, 30 epochs, batch size 256, and all existing scientific gates.
- Keep `formal_target_bundle_generation`, `training`, `formal_prediction_generation`, and `official_scoring` set to `false`.
- Do not create the formal target bundle, train, generate formal predictions, create a one-time scoring authorization, draw the formal 256-bit nonce, or score.
- Do not modify `src/fair_benchmark/frozen/` or the existing scoring, metric, statistic, ledger, input, leakage, or track modules.
- Run only serial synthetic tests whose estimated host peak leaves at least 2 GiB physical and committed-memory headroom.
- Treat protocol hash changes as one atomic cascade across all four experiment configs, the clean-pair contract, source constants, documentation, and the non-observational holdout test vector.

---

### Task 1: Freeze action resource contracts

**Files:**
- Modify: `src/26_historical_band_experts/configs/formal_v09_protocol.json`
- Modify: `src/26_historical_band_experts/formal_v09_protocol.py`
- Modify: `src/26_historical_band_experts/tests/test_formal_v09_protocol.py`

**Interfaces:**
- Consumes: Existing frozen geometry (`531`, `10_501`, `3_288`, `3_652`, `3_562`, batch `256`, model parameter counts).
- Produces: `formal_action_resources` with exact coefficients, accelerator safety factor/reserve, and a fixed target output path.

- [x] **Step 1: Add failing protocol assertions**

```python
assert protocol["formal_action_resources"]["target_bundle"]["writer"] == "stream_one_basin_v1"
assert protocol["formal_action_resources"]["training"]["batch_size"] == 256
assert protocol["formal_action_resources"]["prediction"]["batch_size"] == 256
assert protocol["authorization"]["training"] is False
```

- [x] **Step 2: Run the protocol test and verify the missing contract fails**

Run: `pytest src/26_historical_band_experts/tests/test_formal_v09_protocol.py -q`

Expected: failure for the absent `formal_action_resources` object.

- [x] **Step 3: Add the exact resource contract**

Freeze three distinct estimator method names, formula coefficients, a 1.25 accelerator factor, a 1 GiB accelerator reserve, and `results/26_historical_band_experts/formal_v09/inputs/training_targets.csv` as the only target path. Keep every formal authorization false.

- [x] **Step 4: Run the protocol test through the expected hash-binding failures**

Run: `pytest src/26_historical_band_experts/tests/test_formal_v09_protocol.py -q`

Expected: scientific fields pass and experiment config hash assertions fail until Task 5 performs the atomic hash cascade.

### Task 2: Build strict host and accelerator estimators

**Files:**
- Create: `src/26_historical_band_experts/formal_action_resources_v09.py`
- Modify: `src/fair_benchmark/task_memory_v09.py`
- Modify: `src/26_historical_band_experts/memory_safety_v09.py`
- Create: `src/26_historical_band_experts/tests/test_formal_action_resources_v09.py`
- Modify: `src/26_historical_band_experts/tests/test_memory_safety_v09.py`

**Interfaces:**
- Produces: `build_formal_action_peak_estimate_v09(config, action, variant=None) -> dict`.
- Produces: `validate_formal_action_peak_estimate_v09(config, action, estimate) -> dict`.
- Produces: `AcceleratorMemorySnapshot`, `sample_cuda_memory_v09()`, and `assert_accelerator_safe_v09(...)`.

- [x] **Step 1: Write failing estimator tests**

```python
estimate = build_formal_action_peak_estimate_v09(protocol, "training", variant="classic_lstm_369_capacity")
assert estimate["method"] == "analytical_training_working_set_v1"
assert estimate["evidence"]["batch_size"] == 256
assert estimate["evidence"]["accelerator_estimated_peak_bytes"] > 0
```

Add negative tests that re-hash a smaller batch, row count, parameter count, multiplier, or protocol content hash and still receive `MemorySafetyError`.

- [x] **Step 2: Run the new tests and verify imports/functions are missing**

Run: `pytest src/26_historical_band_experts/tests/test_formal_action_resources_v09.py -q`

Expected: collection or import failure.

- [x] **Step 3: Implement exact formulas and strict schemas**

Use distinct methods:

```text
analytical_target_bundle_working_set_v1
analytical_training_working_set_v1
analytical_prediction_working_set_v1
```

The target formula covers one source basin plus one output chunk because the writer streams. Training and prediction formulas bind forcing rows, five dynamic inputs, batch 256, window 3,562, static width 27, variant hidden sizes, history steps, and exact parameter counts. Accelerator estimates use separate activation multipliers and are never substituted for host estimates.

- [x] **Step 4: Implement accelerator reserve checks**

```python
guarded = math.ceil(estimate_bytes * 1.25)
if snapshot.available_bytes - guarded < 1 * GIB:
    raise MemorySafetyError("accelerator reserve would be crossed")
```

Require CUDA snapshots for training and formal prediction; target construction remains host-only.

- [x] **Step 5: Run estimator and memory tests**

Run: `pytest src/26_historical_band_experts/tests/test_formal_action_resources_v09.py src/26_historical_band_experts/tests/test_memory_safety_v09.py -q`

Expected: all pass.

### Task 3: Add lock-scoped safe runtime entry points

**Files:**
- Create: `src/26_historical_band_experts/formal_action_runtime_v09.py`
- Modify: `src/26_historical_band_experts/launch_gate_v09.py`
- Create: `src/26_historical_band_experts/tests/test_formal_action_runtime_v09.py`
- Modify: `src/26_historical_band_experts/tests/test_launch_gate_v09.py`

**Interfaces:**
- Produces: `audit_formal_action_resources_v09(...) -> dict`, which does not grant authorization.
- Produces: `run_authorized_formal_action_v09(config, action, estimate, operation, ...)`, which holds one lease across launch validation and the complete callback.
- Produces: runtime `checkpoint()` checks between bounded chunks.

- [x] **Step 1: Write failure-order and lifecycle tests**

```python
with pytest.raises(LaunchAuthorizationError):
    run_authorized_formal_action_v09(protocol, "training", estimate, operation)
assert operation_called is False
```

Use monkeypatch only to inspect the internal lifecycle: the lease must be valid during the callback and invalid immediately afterward. Test low physical, low committed, low accelerator, wrong action method, and unavailable CUDA paths.

- [x] **Step 2: Run the runtime tests and verify failure**

Run: `pytest src/26_historical_band_experts/tests/test_formal_action_runtime_v09.py src/26_historical_band_experts/tests/test_launch_gate_v09.py -q`

Expected: missing runtime module and missing action registrations.

- [x] **Step 3: Register methods and implement the runtime**

Bind target construction only to the target method, training only to the training method, prediction only to the prediction method, and scoring only to the existing exact-file method. Validate the action estimate against the current protocol before checking memory.

- [x] **Step 4: Run runtime and launch tests**

Run: `pytest src/26_historical_band_experts/tests/test_formal_action_runtime_v09.py src/26_historical_band_experts/tests/test_launch_gate_v09.py -q`

Expected: all pass and all real formal actions remain rejected by authorization.

### Task 4: Add the bounded formal target builder

**Files:**
- Create: `src/26_historical_band_experts/prepare_targets_formal_v09.py`
- Create: `src/26_historical_band_experts/tests/test_prepare_targets_formal_v09.py`

**Interfaces:**
- Produces: `_write_target_rows_streaming_v09(...)` for isolated synthetic tests.
- Produces: `generate_formal_target_bundle_v09(...)`, the only future formal target entry.

- [x] **Step 1: Write streaming and authorization tests**

```python
manifest = _write_target_rows_streaming_v09(
    basins=("00000001", "00000002"),
    expected_dates=three_days,
    output_path=tmp_path / "targets.csv",
    load_one=synthetic_loader,
    checkpoint=lambda: None,
)
assert manifest["row_count"] == 6
assert manifest["formal_evaluation_rows_emitted"] == 0
```

Also verify duplicate basins, missing/negative values, existing output, temporary-file cleanup, wrong output path, and that the actual protocol rejects before any loader call.

- [x] **Step 2: Run tests and verify the module is missing**

Run: `pytest src/26_historical_band_experts/tests/test_prepare_targets_formal_v09.py -q`

Expected: import failure.

- [x] **Step 3: Implement one-basin streaming and atomic publication**

Write exact columns `basin,date,qobs`, sorted by frozen basin order and date. Write to a temporary file, hash after close, atomically rename, and write a manifest only after the target file is complete. Delete temporary files on every exception. Never return, log, or place target values in the manifest.

- [x] **Step 4: Wrap the builder in the authorization and memory runtime**

Import CAMELS-US streamflow loaders only inside the authorized callback. Check host memory between basins. The fixed output directory must not be created before authorization succeeds.

- [x] **Step 5: Run target tests**

Run: `pytest src/26_historical_band_experts/tests/test_prepare_targets_formal_v09.py -q`

Expected: all pass without reading formal data or creating a formal result directory.

### Task 5: Cascade hashes, regress, audit, and commit atomically

**Files:**
- Modify: four `src/26_historical_band_experts/configs/formal_v09_*.json` experiment configs.
- Modify: `src/26_historical_band_experts/configs/formal_v09_clean_pair_scoring_contract.json`.
- Modify: `src/fair_benchmark/clean_pair_contract_v09.py`.
- Modify: hash-bound preflight and test constants.
- Modify: `docs/plans/2026-07-29-historical-multiscale-formal-v09-handoff.md`.
- Create: `docs/technical/historical_multiscale_formal_v09_action_resources_audit_2026-07-31.md`.

**Interfaces:**
- Produces: one clean commit with protocol raw/canonical hash, clean-pair canonical hash, and non-observational holdout vector all synchronized.

- [x] **Step 1: Recompute all hashes from exact bytes and canonical JSON**

Use Python `hashlib.sha256` over staged bytes and `json.dumps(..., sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False)` for canonical hashes.

- [x] **Step 2: Update the synthetic holdout vector**

Recompute only the non-observational vector using nonce `"1" * 64` and prediction hashes `a/b/c`; do not draw randomness or create a formal holdout.

- [x] **Step 3: Run the affected regression suite under the dynamic host gate**

Run the prior 152-test list plus the three new test files. Record the exact command, count, warning, and elapsed time.

- [x] **Step 4: Independently audit the frozen working tree**

Require the independent reviewer to attempt estimate self-signing, action swapping, geometry shrinking, callback-before-authorization, lease forgery, accelerator bypass, output-before-authorization, hash drift, and protected-path changes.

- [ ] **Step 5: Stage and verify exact staged hashes**

Confirm `git diff --cached --check`, staged protocol raw/canonical hashes, clean-pair canonical hash, authorization fields all false, no formal result directory, and no protected-file diff.

- [ ] **Step 6: Commit one self-consistent change**

```text
Feat: Add formal v09 action resource gates
```

- [ ] **Step 7: Bind the independent conclusion to the new commit**

Verify final HEAD, clean worktree, hashes, authorization closure, absent formal outputs, and protected paths without rerunning unchanged tests.
