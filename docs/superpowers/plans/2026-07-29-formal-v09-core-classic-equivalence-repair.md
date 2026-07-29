# Formal Version 09 Core Classic Equivalence Repair Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the version 09 clean recent control exactly match the real `neuralhydrology.modelzoo.cudalstm.CudaLSTM` recent path in initialization, full-sequence dropout placement, forward predictions, gradients, optimizer state, and random-number-state advancement on synthetic inputs.

**Architecture:** Replace the reused version 08 keyed-final-state model with version 09 classes that mirror the core model's module construction order and apply standard PyTorch dropout to the complete recent recurrent sequence before the regression head. The continuous-history model keeps the same zero-gated history-to-recent state transfer, while inert history construction remains inside `torch.random.fork_rng` so the disabled-history nest has the same active parameters and post-build random-number state as the core-compatible classic.

**Tech Stack:** Python 3, PyTorch 2.2, NeuralHydrology `CudaLSTM`, NeuralHydrology `Config`, pytest, JSON, CSV.

## Global Constraints

- Do not read formal evaluation observations, test result pickles, per-basin evaluation metrics, `usgs_streamflow`, `camels_hydro`, or `*_obs_eval.parquet`.
- Use only the tracked seed-100 baseline configuration at `src/lstm_fair_531/configs/lstm_cudalstm_maurer_531_s100.yml` for the compatibility test.
- Do not generate 531-basin inputs, train a model, create formal predictions, or call the official scorer.
- Preserve 297,217 trainable parameters for the classic and disabled-history models, 595,198 for the capacity control, and 596,737 for the candidate.
- Preserve the recent input order as five Maurer variables followed by 27 static attributes.
- Preserve one recurrent layer, hidden width 256, sequence length 270, full-sequence dropout 0.4, a linear single-flow head, and forget bias 5.
- Same-process core compatibility has zero numerical tolerance.
- The protocol JSON and all four atomic experiment configs must remain hash-bound after the repair.

---

### Task 1: Add a failing core-classic compatibility test

**Files:**
- Create: `src/26_historical_band_experts/tests/test_core_classic_equivalence_v09.py`

**Interfaces:**
- Consumes: `build_model_v09("classic_lstm_256_clean", seed=100)` and a core `CudaLSTM` built from the tracked baseline config.
- Produces: a zero-tolerance test over initialization, input concatenation, training prediction, random-number state, gradients, Adam state, and updated parameters.

- [x] **Step 1: Construct the two models with identical seeds**

```python
cfg = Config(REPO_ROOT / "src/lstm_fair_531/configs/lstm_cudalstm_maurer_531_s100.yml")
torch.manual_seed(100)
core = CudaLSTM(cfg)
core_rng = torch.get_rng_state().clone()
formal = build_model_v09("classic_lstm_256_clean", seed=100)
formal_rng = torch.get_rng_state().clone()
assert torch.equal(core_rng, formal_rng)
```

- [x] **Step 2: Require exact full-sequence training behavior**

```python
before = torch.get_rng_state().clone()
core_prediction = core(core_data)["y_hat"][:, -1, 0]
core_after = torch.get_rng_state().clone()
torch.set_rng_state(before)
formal_prediction = formal({"recent": recent}, statics).prediction
formal_after = torch.get_rng_state().clone()
assert torch.equal(core_prediction, formal_prediction)
assert torch.equal(core_after, formal_after)
```

- [x] **Step 3: Run the test and confirm the current keyed-final-state implementation fails**

Run: `pytest src/26_historical_band_experts/tests/test_core_classic_equivalence_v09.py -q`

Expected: FAIL because the training predictions differ and the post-dropout random-number states are unequal.

### Task 2: Implement the core-compatible version 09 model family

**Files:**
- Modify: `src/26_historical_band_experts/models_formal_v09.py`
- Modify: `src/26_historical_band_experts/tests/test_models_formal_v09.py`
- Test: `src/26_historical_band_experts/tests/test_core_classic_equivalence_v09.py`

**Interfaces:**
- Produces: `CoreCompatibleClassicLSTM`, `CoreCompatibleContinuousHistoryLSTM`, and the unchanged `build_model_v09(variant: str, seed: int) -> nn.Module`.

- [x] **Step 1: Mirror the core module construction order**

```python
self.lstm = nn.LSTM(32, hidden_size, batch_first=True)
self.dropout = nn.Dropout(0.4)
self.head = Regression(n_in=hidden_size, n_out=1, activation="linear")
_set_forget_bias(self.lstm, 5.0)
```

- [x] **Step 2: Apply dropout and the head to the complete recurrent sequence**

```python
encoded, _ = self.lstm(_append_statics(dynamic["recent"], statics))
prediction_sequence = self.head(self.dropout(encoded))["y_hat"]
return ModelOutput(prediction=prediction_sequence[:, -1, 0])
```

- [x] **Step 3: Preserve zero-gated history initialization**

```python
_, (hidden, cell) = self.history_encoder(_append_statics(dynamic["history"], statics))
initial = (
    (torch.tanh(self.hidden_gate) * hidden).contiguous(),
    (torch.tanh(self.cell_gate) * cell).contiguous(),
)
```

- [x] **Step 4: Run model, strict-nesting, and core-equivalence tests**

Run:

`pytest src/26_historical_band_experts/tests/test_models_formal_v09.py src/26_historical_band_experts/tests/test_strict_nesting_formal_v09.py src/26_historical_band_experts/tests/test_core_classic_equivalence_v09.py -q`

Expected: all tests pass with zero maximum difference.

### Task 3: Rebind protocol and audit records

**Files:**
- Modify: `src/26_historical_band_experts/configs/formal_v09_protocol.json`
- Modify: `src/26_historical_band_experts/configs/formal_v09_strict_nesting.json`
- Modify: `src/26_historical_band_experts/configs/formal_v09_classic.json`
- Modify: `src/26_historical_band_experts/configs/formal_v09_capacity.json`
- Modify: `src/26_historical_band_experts/configs/formal_v09_continuous.json`
- Modify: `src/26_historical_band_experts/formal_v09_protocol.py`
- Modify: `src/26_historical_band_experts/registry.csv`
- Modify: `docs/plans/2026-07-29-historical-multiscale-formal-v09-protocol.md`
- Modify: `docs/technical/historical_multiscale_formal_v09_implementation_audit.md`
- Modify: `docs/plans/2026-07-29-historical-multiscale-formal-v09-handoff.md`
- Create: `docs/technical/historical_multiscale_formal_v09_core_classic_repair.md`

**Interfaces:**
- Consumes: the repaired model implementation and zero-tolerance test evidence.
- Produces: a new protocol SHA-256 copied into every atomic arm config and an auditable correction record.

- [x] **Step 1: Replace the dropout contract**

```json
"dropout_stream": "core_torch_rng_full_recent_sequence"
```

- [x] **Step 2: Compute the repaired protocol hash**

Run:

`Get-FileHash -Algorithm SHA256 src/26_historical_band_experts/configs/formal_v09_protocol.json`

Expected: one 64-character SHA-256 copied exactly into all four arm configs.

- [x] **Step 3: Record the pre-repair failure and post-repair evidence**

The repair record must include the observed pre-repair training maximum absolute prediction difference `0.4232901632785797`, unequal post-dropout random-number states, exact evaluation behavior before repair, and zero-tolerance results after repair.

- [x] **Step 4: Run protocol binding tests**

Run: `pytest src/26_historical_band_experts/tests/test_formal_v09_protocol.py -q`

Expected: the repaired protocol and every atomic config have matching hashes and frozen values.

### Task 4: Verify the complete local scope

**Files:**
- Test: `src/26_historical_band_experts/tests`

**Interfaces:**
- Produces: final current-scope GO or NO-GO evidence without formal inputs or training.

- [ ] **Step 1: Run all idea-local tests**

Run: `pytest src/26_historical_band_experts/tests -q`

Expected: all previous tests plus the new core compatibility tests pass.

- [x] **Step 2: Verify frozen and formal-result boundaries**

Run:

```powershell
git diff --name-only 262c8eae785d226e1a51a7b0eaa40660d0bd8c7d -- src/fair_benchmark/frozen src/fair_benchmark/score.py
Test-Path results/26_historical_band_experts/formal_v09
git diff --check
```

Expected: no frozen/scorer changes, no formal result directory, and no whitespace errors.

- [x] **Step 3: Commit the atomic repair**

```powershell
git add docs src/26_historical_band_experts
git commit -m "Fix: Match formal classic path to core LSTM"
```
