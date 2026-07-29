# Historical Multiscale Formal Version 09 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the sealed, leakage-free protocol and lightweight verification code needed before any 531-basin historical multiscale training is allowed.

**Architecture:** A versioned protocol freezes the experiment arms, time geometry, training schedule, information boundary, numerical tolerances, and authorization state. Separate modules enforce host-memory safety, gather causal windows from memory-mapped forcing without expanding every sample, build the clean classic/capacity/history models, check bitwise strict nesting, and validate prediction coverage before the unchanged official scorer is ever called.

**Tech Stack:** Python 3, NumPy, pandas, PyTorch, psutil, pytest, JSON, CSV, optional PyArrow for Parquet prediction chunks.

## Global Constraints

- Use only five Maurer daily forcing columns and 27 static basin attributes.
- Do not read formal-period observed discharge, `usgs_streamflow`, `camels_hydro`, or `*_obs_eval.parquet`.
- Do not modify `src/fair_benchmark/frozen/`, the official scorer, basin lists, or split files.
- The longest lag is 3,561 days; the full causal window contains 3,562 days including the target day.
- The recent path uses lags 0 through 269; the history path uses lags 270 through 3,561 in 120 frozen logarithmic bins.
- The clean classic control has 256 hidden units; the capacity control has 369; the history and recent encoders in the candidate each have 256.
- Use 30 epochs, batch size 256, Adam, gradient clipping 1.0, output dropout 0.4, forget bias 5.0, and learning rates 0.001 for epochs 1-10, 0.0005 for 11-20, and 0.0001 for 21-30.
- Use training seeds 100, 200, 300, 400, 500, 600, 700, and 800; ensemble predictions are averaged in that order in float64.
- Strict nesting inside one environment has zero tolerance for sample keys, predictions, losses, gradients, clipped gradients, optimizer state, and active parameters.
- Independent-environment prediction reproduction uses absolute tolerance `1e-6` and relative tolerance zero.
- The current authorization permits protocol, implementation, and synthetic tests only. It forbids generating the 531-basin target bundle, training, prediction generation, and official scoring.
- Long-running work must start with at least `max(12 GiB, 40% of physical RAM)` available, retain `max(8 GiB, 25% of physical RAM)`, cap the process at `min(6 GiB, 20% of physical RAM)`, and reject a single planned allocation above `min(512 MiB, 2% of physical RAM)`.
- Never materialize all `1,745,928 × 3,562 × 5` training-window values. Read a maximum of one batch of windows from a memory-mapped forcing cube.

---

### Task 1: Freeze the version 09 protocol and experiment registry

**Files:**
- Create: `docs/plans/2026-07-29-historical-multiscale-formal-v09-protocol.md`
- Create: `src/26_historical_band_experts/configs/formal_v09_protocol.json`
- Create: `src/26_historical_band_experts/configs/formal_v09_strict_nesting.json`
- Create: `src/26_historical_band_experts/configs/formal_v09_classic.json`
- Create: `src/26_historical_band_experts/configs/formal_v09_capacity.json`
- Create: `src/26_historical_band_experts/configs/formal_v09_continuous.json`
- Modify: `src/26_historical_band_experts/registry.csv`
- Test: `src/26_historical_band_experts/tests/test_formal_v09_protocol.py`

**Interfaces:**
- Consumes: the frozen Track-0 specification and the audited version 08 candidate.
- Produces: `load_protocol_v09(path: Path) -> dict`, `validate_protocol_v09(config: Mapping) -> None`, and immutable experiment identifiers.

- [ ] **Step 1: Write the failing protocol test**

```python
def test_formal_v09_protocol_freezes_geometry_schedule_and_authorization():
    config = load_protocol_v09(CONFIG_ROOT / "formal_v09_protocol.json")
    validate_protocol_v09(config)
    assert config["history_edges_sha256"] == "55bbdaf654e7ea2b8959cc5dd62de98e4631c272ffe9d7f4efeae9cb7240927b"
    assert config["authorization"]["training"] is False
    assert config["memory_safety"]["long_job_start_available_fraction"] == 0.40
```

- [ ] **Step 2: Run the test and confirm the module is absent**

Run: `pytest src/26_historical_band_experts/tests/test_formal_v09_protocol.py -q`

Expected: collection fails because `formal_v09_protocol` does not exist.

- [ ] **Step 3: Implement the frozen protocol validator**

```python
def learning_rate_for_epoch_v09(epoch: int) -> float:
    if not 1 <= epoch <= 30:
        raise ValueError("epoch must be in 1..30")
    if epoch <= 10:
        return 0.001
    if epoch <= 20:
        return 0.0005
    return 0.0001
```

- [ ] **Step 4: Run the protocol tests**

Run: `pytest src/26_historical_band_experts/tests/test_formal_v09_protocol.py -q`

Expected: all protocol and registry assertions pass.

### Task 2: Enforce host-memory safety

**Files:**
- Create: `src/26_historical_band_experts/memory_safety_v09.py`
- Create: `src/26_historical_band_experts/launch_gate_v09.py`
- Test: `src/26_historical_band_experts/tests/test_memory_safety_v09.py`
- Test: `src/26_historical_band_experts/tests/test_launch_gate_v09.py`

**Interfaces:**
- Consumes: `HostMemorySnapshot(total_bytes, available_bytes, process_rss_bytes)`.
- Produces: `MemorySafetyPolicy.from_total(total_bytes)`, `MemorySafetyGate.assert_start_safe(...)`, `MemorySafetyGate.assert_runtime_safe(...)`, `MemorySafetyGate.assert_allocation_safe(...)`, and `assert_launch_allowed_v09(...)`.

- [ ] **Step 1: Write failure-path tests**

```python
def test_long_job_is_blocked_with_only_ten_gib_available():
    snapshot = HostMemorySnapshot(32 * GIB, 10 * GIB, 1 * GIB)
    with pytest.raises(MemorySafetyError, match="start available"):
        MemorySafetyGate.from_snapshot(snapshot).assert_start_safe(2 * GIB, long_running=True)


def test_full_training_window_expansion_is_blocked():
    gate = MemorySafetyGate.from_snapshot(HostMemorySnapshot(32 * GIB, 20 * GIB, 1 * GIB))
    with pytest.raises(MemorySafetyError, match="single allocation"):
        gate.assert_allocation_safe((1_745_928, 3_562, 5), np.float32)
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `pytest src/26_historical_band_experts/tests/test_memory_safety_v09.py -q`

Expected: collection fails because `memory_safety_v09` does not exist.

- [ ] **Step 3: Implement dynamic thresholds and psutil sampling**

```python
reserve_bytes = max(8 * GIB, math.ceil(0.25 * total_bytes))
long_start_bytes = max(12 * GIB, math.ceil(0.40 * total_bytes))
process_limit_bytes = min(6 * GIB, math.floor(0.20 * total_bytes))
single_allocation_limit_bytes = min(512 * MIB, math.floor(0.02 * total_bytes))
```

- [ ] **Step 4: Run memory tests**

Run: `pytest src/26_historical_band_experts/tests/test_memory_safety_v09.py -q`

Expected: long-job, reserve, process-limit, and allocation-limit paths all pass.

### Task 3: Implement causal batch-window extraction and model construction

**Files:**
- Create: `src/26_historical_band_experts/bands_formal_v09.py`
- Create: `src/26_historical_band_experts/models_formal_v09.py`
- Test: `src/26_historical_band_experts/tests/test_bands_formal_v09.py`
- Test: `src/26_historical_band_experts/tests/test_models_formal_v09.py`

**Interfaces:**
- Consumes: a float32 forcing array or memory map shaped `[basin, time, 5]`, batch basin indices, and batch target indices.
- Produces: `gather_causal_windows_v09(...) -> np.ndarray`, `split_windows_v09(windows: torch.Tensor) -> dict[str, torch.Tensor]`, and `build_model_v09(variant: str, seed: int) -> nn.Module`.

- [ ] **Step 1: Write chronological and causality tests**

```python
def test_window_split_covers_each_lag_once():
    window = torch.arange(3562, dtype=torch.float64).reshape(1, 3562, 1).repeat(1, 1, 5)
    dynamic = split_windows_v09(window)
    assert dynamic["recent"][0, 0, 0] == 3292
    assert dynamic["recent"][0, -1, 0] == 3561
    assert dynamic["history"].shape == (1, 120, 7)
```

- [ ] **Step 2: Run the tests and confirm the modules are absent**

Run: `pytest src/26_historical_band_experts/tests/test_bands_formal_v09.py src/26_historical_band_experts/tests/test_models_formal_v09.py -q`

Expected: collection fails for missing version 09 modules.

- [ ] **Step 3: Implement one-batch allocation and frozen models**

```python
output = np.empty((len(basin_indices), 3562, 5), dtype=np.float32)
for row, (basin_index, target_index) in enumerate(zip(basin_indices, target_indices)):
    output[row] = forcing[basin_index, target_index - 3561:target_index + 1]
```

The model builder returns the clean 256-unit classic model, 369-unit capacity control, disabled-history strict nest, or the 256-unit recent plus 256-unit zero-gated history candidate.

- [ ] **Step 4: Run band and model tests**

Run: `pytest src/26_historical_band_experts/tests/test_bands_formal_v09.py src/26_historical_band_experts/tests/test_models_formal_v09.py -q`

Expected: geometry, causality, parameter counts, one-output structure, and exact initial identity all pass.

### Task 4: Add strict nesting and memory-safe prediction preflight

**Files:**
- Create: `src/26_historical_band_experts/strict_nesting_formal_v09.py`
- Create: `src/26_historical_band_experts/prediction_preflight_v09.py`
- Test: `src/26_historical_band_experts/tests/test_strict_nesting_formal_v09.py`
- Test: `src/26_historical_band_experts/tests/test_prediction_preflight_v09.py`

**Interfaces:**
- Produces: `lockstep_train_step_v09(...) -> dict`, `assert_reproduced_predictions_v09(...) -> None`, `validate_exact_prediction_coverage_v09(...) -> dict`, and `compose_seed_mean_v09(...) -> dict`.

- [ ] **Step 1: Write strict-equality and malformed-prediction tests**

```python
def test_one_lockstep_update_is_bitwise_exact():
    report = lockstep_train_step_v09(classic, nested, classic_optimizer, nested_optimizer,
                                    dynamic, statics, target, weights, context=(100, 1, 0))
    assert report["lockstep_exact"] is True


def test_duplicate_prediction_key_is_rejected(tmp_path):
    path = write_predictions(tmp_path, duplicate=True)
    with pytest.raises(PredictionPreflightError, match="duplicate"):
        validate_exact_prediction_coverage_v09(path, ("00000001",), "2000-01-01", "2000-01-02")
```

- [ ] **Step 2: Run tests and confirm the modules are absent**

Run: `pytest src/26_historical_band_experts/tests/test_strict_nesting_formal_v09.py src/26_historical_band_experts/tests/test_prediction_preflight_v09.py -q`

Expected: collection fails for missing version 09 modules.

- [ ] **Step 3: Implement lockstep checks and chunked prediction handling**

The strict step checks active parameter names and values, keyed-dropout predictions, weighted loss, unclipped gradients, clipped gradients, Adam state, and updated parameters with `torch.equal`. Prediction preflight reads CSV or Parquet in chunks, encodes basin-date keys into a boolean bitmap, rejects duplicate/missing/nonfinite rows, and never opens observed discharge.

- [ ] **Step 4: Run strict and prediction tests**

Run: `pytest src/26_historical_band_experts/tests/test_strict_nesting_formal_v09.py src/26_historical_band_experts/tests/test_prediction_preflight_v09.py -q`

Expected: exact equality, `1e-6` reproduction tolerance, duplicate/missing/nonfinite rejection, and eight-seed float64 averaging pass.

### Task 5: Verify scope and prepare the approval handoff

**Files:**
- Create: `docs/plans/2026-07-29-historical-multiscale-formal-v09-handoff.md`
- Do not create: any file under `results/26_historical_band_experts/formal_v09/`

**Interfaces:**
- Produces: a self-contained continuation prompt and an explicit GO/NO-GO statement for the later data-build/training phase.

- [ ] **Step 1: Format only the new Python files**

Run: `yapf -i src/26_historical_band_experts/*_v09.py src/26_historical_band_experts/tests/test_*_v09.py`

Expected: only version 09 files change.

- [ ] **Step 2: Run the version 09 suite**

Run: `pytest src/26_historical_band_experts/tests/test_*v09.py -q`

Expected: every lightweight synthetic test passes without creating formal data, predictions, or score-ledger entries.

- [ ] **Step 3: Run the complete idea-local suite**

Run: `pytest src/26_historical_band_experts/tests -q`

Expected: all prior tests and the new version 09 tests pass.

- [ ] **Step 4: Perform the self-review**

Run:

```powershell
git status --short
git diff --check
rg -n "usgs_streamflow|camels_hydro|obs_eval|score_submission|track0_forcing_only_obs" src/26_historical_band_experts/*v09.py
Test-Path results/26_historical_band_experts/formal_v09
```

Expected: no whitespace errors; version 09 code contains no forbidden reader or official scoring call; the formal result directory does not exist.

- [ ] **Step 5: Write the handoff with the live memory decision**

The handoff records the 31.70 GiB host total, the observed available-memory snapshot, the 12.68 GiB long-job start requirement, the 8 GiB reserve, the current training prohibition, exact approval needed next, and a clean-context continuation prompt.
