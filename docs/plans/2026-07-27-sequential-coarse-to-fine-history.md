# Sequential Coarse-to-Fine History Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build and internally evaluate a single-output rainfall-runoff model that transfers complete recurrent state from old history to medium history and then to recent daily forcing.

**Architecture:** Three one-layer, hidden-width-256 Long Short-Term Memory encoders process the existing disjoint old, medium, and recent bands in chronological order. The old final hidden and cell states initialize the medium encoder, the medium final states initialize the recent encoder, and one linear head reads only the recent final state. Existing frozen data, training protocol, deterministic dropout, controls, and first-stage gates remain unchanged.

**Tech Stack:** Python 3, PyTorch, NumPy, pandas, pytest, existing `src/26_historical_band_experts` data and metric utilities.

---

### Task 1: Freeze configurations and registry contract

**Files:**
- Create: `src/26_historical_band_experts/configs/sequential_transfer_s01_v07.json`
- Create: `src/26_historical_band_experts/configs/sequential_transfer_s01_smoke_v07.json`
- Modify: `src/26_historical_band_experts/registry.csv`
- Test: `src/26_historical_band_experts/tests/test_sequential_transfer_v07.py`

**Step 1: Write the failing configuration test**

Test that the pilot and smoke configurations contain:

- experiment ID `E07-S01`;
- fixed basin and target hashes;
- old, medium, and recent lag intervals;
- three hidden widths equal to 256;
- candidate parameter count 891,137;
- capacity-control parameter count 890,436;
- unchanged first-stage gates;
- pilot has no batch or validation limit;
- smoke has two epochs and positive limits;
- formal evaluation access is false.

**Step 2: Run the test to verify it fails**

Run:

```powershell
pytest -q src/26_historical_band_experts/tests/test_sequential_transfer_v07.py
```

Expected: failure because the new configurations do not exist.

**Step 3: Add the minimal configurations and registry row**

Use one experiment ID, one configuration per mode, one output root, and one registry row. Bind the existing strict-nesting summary and legacy late-concatenation predictions by SHA-256.

**Step 4: Run the test to verify it passes**

Run the same pytest command. Expected: configuration test passes while later model tests still fail or are absent.

**Step 5: Commit**

```powershell
git add src/26_historical_band_experts/configs src/26_historical_band_experts/registry.csv src/26_historical_band_experts/tests/test_sequential_transfer_v07.py
git commit -m "Phase: preregister sequential history transfer"
```

### Task 2: Implement the sequential model with test-first state tracing

**Files:**
- Create: `src/26_historical_band_experts/models_sequential_v07.py`
- Modify: `src/26_historical_band_experts/tests/test_sequential_transfer_v07.py`

**Step 1: Write failing model tests**

Tests must require:

1. three recurrent modules with input width 32 and hidden width 256;
2. exactly one output head;
3. total parameter count 891,137;
4. recent encoder and head copied exactly from a same-seed keyed classic model;
5. prediction shape `[batch]`;
6. changing old inputs changes the final prediction;
7. changing medium inputs changes the final prediction;
8. gradients reach old, medium, and recent recurrent weights;
9. diagnostic reset modes `none`, `old_to_medium`, `medium_to_recent`, and `both` have the specified state-flow behavior;
10. `both` reset produces exactly the copied recent path in evaluation mode.

Use forward hooks on recurrent modules to capture the actual initial states received by medium and recent encoders. Assert equality to the preceding encoder's final states.

**Step 2: Run tests and verify the expected failure**

Expected: import failure for `models_sequential_v07`.

**Step 3: Implement the minimal model**

Create:

```python
class SequentialHistoricalLSTM(nn.Module):
    consumed_dynamic_keys = ("recent", "medium", "old")

    def forward(self, dynamic, statics, dropout_context=None, reset_mode="none"):
        _, old_state = self.old_encoder(_append_statics(dynamic["old"], statics))
        medium_initial = zero_state(old_state) if reset_old else old_state
        _, medium_state = self.medium_encoder(
            _append_statics(dynamic["medium"], statics), medium_initial
        )
        recent_initial = zero_state(medium_state) if reset_medium else medium_state
        recent, _ = self.recent_encoder(
            _append_statics(dynamic["recent"], statics), recent_initial
        )
        state = keyed_dropout(
            recent[:, -1], self.dropout_probability, dropout_context, "recent", self.training
        )
        return ModelOutput(prediction=self.head(state)[:, 0])
```

Build the same-seed classic model first, then create the candidate and copy its recurrent state and head.

**Step 4: Run model tests**

Expected: all model and state-flow tests pass.

**Step 5: Run existing strict and equal-expert tests**

```powershell
pytest -q src/26_historical_band_experts/tests/test_models_v06.py src/26_historical_band_experts/tests/test_equal_experts_v06.py
```

Expected: no regression.

**Step 6: Commit**

```powershell
git add src/26_historical_band_experts/models_sequential_v07.py src/26_historical_band_experts/tests/test_sequential_transfer_v07.py
git commit -m "Feat: add sequential historical state transfer"
```

### Task 3: Implement the frozen training and artifact contract

**Files:**
- Create: `src/26_historical_band_experts/train_sequential_v07.py`
- Modify: `src/26_historical_band_experts/tests/test_sequential_transfer_v07.py`

**Step 1: Write failing training tests**

Require:

- configuration validation rejects changed bands, widths, hashes, gates, or formal access;
- classic and capacity controls receive only recent inputs;
- sequential candidate receives all three bands;
- all variants use identical training coordinates and batch order;
- keyed recent dropout uses the same `(seed, epoch, batch)` context;
- one training step updates candidate old, medium, and recent parameters;
- a smoke run writes config, checkpoint, predictions, per-basin metrics, state diagnostics, and manifest;
- manifest records model inputs, parameter count, epochs, optimizer steps, formal access false, and raw observed discharge reads zero;
- output directory must be empty.

**Step 2: Run tests and verify failure**

Expected: import failure for `train_sequential_v07`.

**Step 3: Implement the minimal trainer**

Reuse:

- `load_data_pack`, `compute_scaler`, `normalize_pack`, and `split_target_indices`;
- `gather_fixed_bands_v03`;
- deterministic keyed dropout;
- current loss weighting, learning-rate schedule, Adam optimizer, and gradient clipping;
- atomic writes and SHA-256 helpers.

Do not select checkpoints on validation results. Save the final epoch only.

**Step 4: Run focused tests**

Expected: focused sequential tests pass.

**Step 5: Commit**

```powershell
git add src/26_historical_band_experts/train_sequential_v07.py src/26_historical_band_experts/tests/test_sequential_transfer_v07.py
git commit -m "Feat: add sequential transfer training contract"
```

### Task 4: Implement analysis, paired gates, and state-reset diagnostics

**Files:**
- Create: `src/26_historical_band_experts/analyze_sequential_v07.py`
- Modify: `src/26_historical_band_experts/tests/test_sequential_transfer_v07.py`

**Step 1: Write failing analysis tests**

Require:

- exact basin/date/observation alignment among candidate and all controls;
- per-basin paired efficiency differences;
- four frozen first-stage gates;
- conditional seeds requested only if all first-stage gates pass;
- multi-seed gates evaluated only when all required runs exist;
- state-reset diagnostic prediction files and paired metrics;
- no inference of causal contribution from reset diagnostics;
- summary and manifest hashes.

**Step 2: Run tests and verify failure**

Expected: import failure for `analyze_sequential_v07`.

**Step 3: Implement the minimal analyzer**

Use existing metric helpers and explicit comparisons. Refuse to analyze any key or observation mismatch.

**Step 4: Run focused tests**

Expected: all sequential tests pass.

**Step 5: Commit**

```powershell
git add src/26_historical_band_experts/analyze_sequential_v07.py src/26_historical_band_experts/tests/test_sequential_transfer_v07.py
git commit -m "Feat: add sequential transfer analysis gates"
```

### Task 5: Execute smoke verification

**Files:**
- Outputs: `results/26_historical_band_experts/sequential_coarse_to_fine_v07_smoke/`

**Step 1: Run the full local test suite**

```powershell
pytest -q src/26_historical_band_experts/tests
```

Expected: zero failures.

**Step 2: Run three smoke arms on the available device**

Run classic 256, capacity 455, and sequential candidate with the smoke configuration, seed 100, frozen target SHA-256, and allowed data directory.

**Step 3: Verify smoke manifests**

Require finite losses, expected parameter counts, expected row counts, candidate gradients in all three recurrent modules, and formal access false.

**Step 4: Run smoke analysis**

Expected: complete interface status. Do not interpret smoke metrics as scientific evidence.

**Step 5: Commit only code or documentation changes**

Result outputs remain isolated under `results/`.

### Task 6: Run first-stage internal experiment

**Files:**
- Outputs: `results/26_historical_band_experts/sequential_coarse_to_fine_v07/`

**Step 1: Confirm resource headroom and no competing training process**

Record graphics processor model, memory availability, PyTorch and CUDA versions.

**Step 2: Train seed 100 controls and candidate**

Run classic 256, capacity 455, and sequential candidate. Each must complete 30 epochs and 18,000 optimizer steps.

**Step 3: Run state-reset diagnostics**

Evaluate the frozen candidate checkpoint under all four reset modes for 43,860 validation samples.

**Step 4: Run first-stage analysis**

Freeze the summary before making any next-run decision.

**Step 5: Apply the pre-registered stop rule**

- If any first-stage gate fails, do not train seeds 200 or 300.
- If all pass, record the gate decision and continue.

### Task 7: Conditional multi-seed confirmation

**Files:**
- Outputs: additional seed-specific directories under the version 07 result root.

**Step 1: Train seeds 200 and 300 only when authorized by Task 6**

Use matched classic, capacity, and candidate arms for each seed.

**Step 2: Analyze all seeds without selecting a subset**

Compute seed-wise and combined paired metrics, bootstrap interval, win fraction, and control comparisons.

**Step 3: Freeze final scientific status**

Use one of:

- `complete_multiseed_go_internal`;
- `complete_multiseed_no_go`;
- `complete_stage1_no_go`;
- `audit_failure`.

Do not open formal evaluation.

### Task 8: Local reproducibility audit and technical report

**Files:**
- Create: `docs/technical/sequential_coarse_to_fine_history_v07.md`
- Modify: `src/26_historical_band_experts/registry.csv`

**Step 1: Verify artifact chain**

Map experiment ID → configuration → seed → checkpoint → predictions → per-basin metrics → summary → report.

**Step 2: Independently recompute saved metrics**

Use a read-only audit script or one-off command that does not import the analyzer's comparison functions.

**Step 3: Verify all saved hashes**

Reject any mismatch.

**Step 4: Write the technical report**

Separate facts, inferences, limitations, and unknown formal performance.

**Step 5: Run the full test suite and repository checks**

```powershell
pytest -q src/26_historical_band_experts/tests
git diff --check
git status --short
```

**Step 6: Commit**

```powershell
git add docs/technical/sequential_coarse_to_fine_history_v07.md src/26_historical_band_experts/registry.csv
git commit -m "Phase: freeze sequential history transfer result"
```

### Task 9: Independent adversarial audit

**Files:**
- Create: `docs/technical/sequential_coarse_to_fine_history_v07_independent_audit.md`

**Step 1: Dispatch a fresh independent context**

Provide only the frozen design path, configuration path, result root, branch, and audit requirements. Do not provide the implementer's preferred conclusion.

**Step 2: Require adversarial checks**

The auditor must inspect code, independently recompute metrics, verify hashes and input boundaries, and try to refute the result.

**Step 3: Inspect the auditor's evidence**

The primary agent must not trust the audit report alone. Re-run any decisive command or inspect the cited artifact.

**Step 4: Commit the audit**

```powershell
git add docs/technical/sequential_coarse_to_fine_history_v07_independent_audit.md
git commit -m "Phase: record independent sequential transfer audit"
```

### Task 10: Final requirement-by-requirement completion audit

**Step 1: Re-read the approved design and this implementation plan**

Create a checklist for every required artifact, command, gate, boundary, and deliverable.

**Step 2: Gather fresh final evidence**

Run full tests, hash verification, branch/status checks, and process checks.

**Step 3: State the narrowest defensible conclusion**

Distinguish:

- whether the implementation is correct;
- whether the state-transfer mechanism is used;
- whether internal predictive performance improves;
- whether improvement is stable across seeds;
- whether formal performance is known.

**Step 4: Mark the user goal complete only if implementation, experiment, local audit, and independent audit are all finished**

