# Continuous Multiscale History Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build, run, and independently audit a one-shot continuous multiscale historical-forcing experiment with exact classic-model nesting and a fresh internal confirmation window.

**Architecture:** A new version 08 module extracts one chronological 120-token history sequence using frozen logarithmic lag edges, appends deterministic duration and age coordinates, and uses a zero-gated history long short-term memory state to initialize an unchanged recent 270-day long short-term memory path. A new trainer owns the fresh time split, exact nested reproduction, atomic artifacts, staged seed policy, and persisted-prediction recomputation without modifying version 03–07 results.

**Tech Stack:** Python 3, PyTorch, NumPy, pandas, pytest, existing allowed-input CAMELS-US loaders and historical-band metric helpers.

## Global Constraints

- Only Maurer five-variable meteorological forcing and 27 frozen static attributes may enter a model.
- Do not read formal-evaluation observations, predictions, answer keys, `usgs_streamflow`, `camels_hydro`, or `*_obs_eval.parquet`.
- Do not modify `src/fair_benchmark/frozen/`, formal scoring code, basin files, target bundles, or version 03–07 artifacts.
- Training targets are 1999-10-01 through 2004-09-30; confirmation targets are 2004-10-01 through 2006-09-30.
- Experiment outputs are isolated under `results/26_historical_band_experts/continuous_multiscale_history_v08*`.
- Strict nesting uses zero numerical tolerance; seed 100 failure stops seeds 200 and 300.
- Every metric is computed from reloaded persisted predictions.

---

### Task 1: Freeze version 08 identities and protocol

**Files:**
- Create: `src/26_historical_band_experts/configs/continuous_multiscale_c01_v08.json`
- Create: `src/26_historical_band_experts/configs/continuous_multiscale_c01_smoke_v08.json`
- Modify: `src/26_historical_band_experts/registry.csv`
- Test: `src/26_historical_band_experts/tests/test_continuous_multiscale_v08.py`

**Interfaces:**
- Consumes: frozen basin and target hashes plus the design document.
- Produces: one pilot configuration, one smoke configuration, and registry rows `R08-NEST` and `E08-C01`.

- [ ] **Step 1: Write failing configuration tests**

```python
def test_v08_configs_freeze_new_split_geometry_and_gates():
    pilot = _load("continuous_multiscale_c01_v08.json")
    assert pilot["experiment_family"] == "continuous_multiscale_history_v08"
    assert pilot["train_period"] == ["1999-10-01", "2004-09-30"]
    assert pilot["confirmation_period"] == ["2004-10-01", "2006-09-30"]
    assert pilot["expected_training_samples"] == 109_620
    assert pilot["expected_confirmation_predictions"] == 43_800
    assert pilot["history_lags"] == [270, 3649]
    assert pilot["history_bins"] == 120
    assert pilot["history_edges_sha256"] == "bae1f744feca9160181365545a07b445eab269d6afa8817a2e7c99e19f200d73"
    assert pilot["candidate_parameter_count"] == 596_737
    assert pilot["capacity_control_parameter_count"] == 595_198
    assert pilot["formal_evaluation_access"] is False
```

- [ ] **Step 2: Run the missing-file failure**

Run: `pytest src/26_historical_band_experts/tests/test_continuous_multiscale_v08.py -q`

Expected: fail because version 08 configurations and registry rows do not exist.

- [ ] **Step 3: Add immutable configurations and registry rows**

The pilot config fixes 30 epochs, batches 256/512, seeds 100 then conditional 200/300, learning rates 0.001/0.0005/0.0001 at epochs 1/12/22, gradient clip 1.0, dropout 0.4, forget bias 5.0, bootstrap 100,000 with seed 20260728, and all four stage-one gates. The smoke config fixes 2 epochs, 2 training batches, and 1,024 confirmation samples.

- [ ] **Step 4: Re-run the configuration tests**

Run: `pytest src/26_historical_band_experts/tests/test_continuous_multiscale_v08.py -q`

Expected: configuration and registry assertions pass; later missing-module tests may still fail.

- [ ] **Step 5: Commit the frozen protocol**

Run: `git add docs/plans/2026-07-28-continuous-multiscale-history-design.md docs/superpowers/plans/2026-07-28-continuous-multiscale-history.md src/26_historical_band_experts/configs/continuous_multiscale_c01_v08.json src/26_historical_band_experts/configs/continuous_multiscale_c01_smoke_v08.json src/26_historical_band_experts/registry.csv src/26_historical_band_experts/tests/test_continuous_multiscale_v08.py && git commit -m "Phase: freeze continuous multiscale history protocol"`

### Task 2: Implement causal continuous history extraction

**Files:**
- Create: `src/26_historical_band_experts/bands_continuous_v08.py`
- Modify: `src/26_historical_band_experts/tests/test_continuous_multiscale_v08.py`

**Interfaces:**
- Produces: `continuous_history_edges_v08() -> np.ndarray` and `gather_continuous_history_v08(forcing, prefix, basin_indices, target_indices) -> dict[str, torch.Tensor]`.
- Output keys: `recent` with shape `[batch, 270, 5]`; `history` with shape `[batch, 120, 7]`.

- [ ] **Step 1: Add failing geometry tests**

```python
def test_v08_edges_cover_every_historical_lag_once():
    edges = continuous_history_edges_v08()
    assert edges.shape == (121,)
    assert edges[0] == 270 and edges[-1] == 3650
    assert np.all(np.diff(edges) > 0)
    assert np.diff(edges).sum() == 3380
    assert _edge_hash(edges) == "bae1f744feca9160181365545a07b445eab269d6afa8817a2e7c99e19f200d73"
```

Add an integer-ramp extraction test that independently computes every block mean, verifies oldest-to-recent order, verifies no lag below 270 or above 3649 is read, and checks both metadata coordinates.

- [ ] **Step 2: Run the missing-module failure**

Run: `pytest src/26_historical_band_experts/tests/test_continuous_multiscale_v08.py -q`

Expected: fail importing `bands_continuous_v08`.

- [ ] **Step 3: Implement the extractor**

```python
def continuous_history_edges_v08() -> np.ndarray:
    edges = np.rint(
        np.exp(np.linspace(np.log(270.0), np.log(3650.0), 121))
    ).astype(np.int64)
    edges[0], edges[-1] = 270, 3650
    if np.any(np.diff(edges) <= 0):
        raise ValueError("history edges must be strictly increasing")
    return edges
```

Use cumulative sums for the five forcing means. Append duration and midpoint-lag coordinates after aggregation. Reverse the edge intervals so sequence order is oldest to most recent.

- [ ] **Step 4: Run focused and version 03 band tests**

Run: `pytest src/26_historical_band_experts/tests/test_continuous_multiscale_v08.py src/26_historical_band_experts/tests/test_bands_v03.py -q`

Expected: all pass.

- [ ] **Step 5: Commit extraction**

Run: `git add src/26_historical_band_experts/bands_continuous_v08.py src/26_historical_band_experts/tests/test_continuous_multiscale_v08.py && git commit -m "Feat: add continuous multiscale history bins"`

### Task 3: Implement zero-gated history and exact nested model

**Files:**
- Create: `src/26_historical_band_experts/models_continuous_v08.py`
- Modify: `src/26_historical_band_experts/tests/test_continuous_multiscale_v08.py`

**Interfaces:**
- Produces: `ContinuousMultiscaleHistoryLSTM`, `build_model_v08(variant: str, seed: int)`.
- Variants: `classic_lstm_256_keyed`, `classic_lstm_369_keyed`, `nested_history_disabled`, `continuous_multiscale_history`.

- [ ] **Step 1: Add failing structure and nesting tests**

```python
def test_v08_candidate_structure_counts_and_zero_gate_identity():
    classic = build_model_v08("classic_lstm_256_keyed", 100)
    candidate = build_model_v08("continuous_multiscale_history", 100)
    assert count_trainable_parameters(candidate) == 596_737
    assert torch.count_nonzero(candidate.hidden_gate).item() == 0
    assert torch.count_nonzero(candidate.cell_gate).item() == 0
    candidate.train()
    classic.train()
    actual = candidate(dynamic, statics, dropout_context=(100, 1, 0)).prediction
    expected = classic(dynamic, statics, dropout_context=(100, 1, 0)).prediction
    assert torch.equal(actual, expected)
```

Also assert one output, history input 34, recent input 32, hidden width 256, capacity count 595,198, disabled history not consumed, and active disabled-model parameter names/order/values equal classic.

- [ ] **Step 2: Run the missing-model failure**

Run: `pytest src/26_historical_band_experts/tests/test_continuous_multiscale_v08.py -q`

Expected: fail importing `models_continuous_v08`.

- [ ] **Step 3: Implement the model**

Subclass the keyed classic model so `lstm` and `head` stay the first registered modules. Add `history_encoder`, `hidden_gate`, and `cell_gate`; initialize gates to zero. Candidate forward computes:

```python
_, (history_hidden, history_cell) = self.history_encoder(history_with_statics)
initial = (
    torch.tanh(self.hidden_gate) * history_hidden,
    torch.tanh(self.cell_gate) * history_cell,
)
recent, _ = self.lstm(recent_with_statics, initial)
prediction = self.head(keyed_dropout(recent[:, -1], ...))[:, 0]
```

The disabled variant freezes and skips all history objects and executes the inherited recent-only forward.

- [ ] **Step 4: Run focused tests**

Run: `pytest src/26_historical_band_experts/tests/test_continuous_multiscale_v08.py src/26_historical_band_experts/tests/test_models_v06.py src/26_historical_band_experts/tests/test_sequential_transfer_v07.py -q`

Expected: all pass.

- [ ] **Step 5: Commit model**

Run: `git add src/26_historical_band_experts/models_continuous_v08.py src/26_historical_band_experts/tests/test_continuous_multiscale_v08.py && git commit -m "Feat: add zero-gated continuous history model"`

### Task 4: Implement fresh split, atomic training, and exact reproduction

**Files:**
- Create: `src/26_historical_band_experts/train_continuous_v08.py`
- Modify: `src/26_historical_band_experts/tests/test_continuous_multiscale_v08.py`

**Interfaces:**
- Produces: `validate_config_v08`, `split_target_indices_v08`, `compute_scaler_v08`, `run_experiment_v08`, and `run_strict_reproduction_v08`.
- Reuses: `lockstep_train_step` and exact tensor checks from `train_strict_v06.py`.

- [ ] **Step 1: Add failing split and scaler tests**

Create a synthetic data pack whose confirmation-period values are extreme. Require exactly 109,620/43,800 pilot counts by configuration and prove those extreme confirmation values do not affect forcing, target, or per-basin loss scaling.

- [ ] **Step 2: Add failing atomic-run tests**

Require isolated nonempty-directory rejection, allowed seeds only, exact artifact set, output rows from the configured confirmation period only, persisted-prediction metric recomputation, checkpoint scaler provenance, finite gradients, and access counters:

```python
assert manifest["data_access"] == {
    "raw_observed_discharge_reads": 0,
    "target_bundle_interface": True,
    "formal_evaluation_target_access": False,
    "earliest_forcing_date": "1989-10-04",
}
```

- [ ] **Step 3: Add a failing two-epoch lockstep test**

Require classic and disabled-history nested models to match predictions, losses, gradients, clipped gradients, Adam states, parameters, and confirmation predictions with zero tolerance.

- [ ] **Step 4: Implement split/scaler and runners**

Keep version 08 periods local to this module. Do not change `data.py` defaults. Build dynamic batches through `gather_continuous_history_v08` for the candidate and recent-only batches for controls. Save config, checkpoint, predictions, reloaded metrics, diagnostics, manifest, and hashes atomically.

- [ ] **Step 5: Run focused tests**

Run: `pytest src/26_historical_band_experts/tests/test_continuous_multiscale_v08.py -q`

Expected: all focused tests pass.

- [ ] **Step 6: Commit training and reproduction**

Run: `git add src/26_historical_band_experts/train_continuous_v08.py src/26_historical_band_experts/tests/test_continuous_multiscale_v08.py && git commit -m "Feat: add fresh-split continuous history training"`

### Task 5: Implement frozen analysis and diagnostics

**Files:**
- Create: `src/26_historical_band_experts/analyze_continuous_v08.py`
- Modify: `src/26_historical_band_experts/tests/test_continuous_multiscale_v08.py`

**Interfaces:**
- Produces: `evaluate_stage1_v08`, `evaluate_multiseed_v08`, `run_history_gate_diagnostic_v08`, `analyze_results_v08`.

- [ ] **Step 1: Add failing gate tests**

Create synthetic paired basin metrics that separately fail each of the four gates and one case that passes all. Assert strict inequalities exactly as frozen in the design.

- [ ] **Step 2: Add failing artifact-validation tests**

Require identical basin/date/observation keys across arms, manifest identity and hash checks, exact metrics recomputation from persisted predictions, 60 pilot basins, and 43,800 predictions per arm.

- [ ] **Step 3: Add failing gate-zero diagnostic tests**

Load a tiny candidate checkpoint, write normal and gate-zero predictions, recompute both metric files after CSV reload, and record parameter drift and gate/state norms without causal language.

- [ ] **Step 4: Implement analysis**

Use 100,000 basin bootstrap samples with seed 20260728. Emit `complete_stage1_no_go`, `complete_stage1_go_pending_multiseed`, or a final multi-seed status. Never infer authorization for conditional seeds from partial gate success.

- [ ] **Step 5: Run focused tests**

Run: `pytest src/26_historical_band_experts/tests/test_continuous_multiscale_v08.py -q`

Expected: all pass.

- [ ] **Step 6: Commit analysis**

Run: `git add src/26_historical_band_experts/analyze_continuous_v08.py src/26_historical_band_experts/tests/test_continuous_multiscale_v08.py && git commit -m "Feat: add continuous history analysis gates"`

### Task 6: Verify and run the staged experiment

**Files:**
- Outputs: `results/26_historical_band_experts/continuous_multiscale_history_v08_smoke/`
- Outputs: `results/26_historical_band_experts/continuous_multiscale_history_v08/`
- Modify after evidence: `src/26_historical_band_experts/registry.csv`
- Create after evidence: `docs/technical/continuous_multiscale_history_v08.md`

**Interfaces:**
- Consumes: frozen version 08 code/config and the allowed data roots.
- Produces: exact nested reproduction, seed-100 candidate/control artifacts, conditional multi-seed artifacts only when authorized, a technical report, and final registry status.

- [ ] **Step 1: Run all local tests before graphics-processor work**

Run: `pytest src/26_historical_band_experts/tests -q`

Expected: all pass with only the pre-existing unknown `collect_ignore_glob` warning.

- [ ] **Step 2: Run graphics-processor smoke reproduction and all variants**

Run the smoke config for `R08-NEST`, `classic_lstm_256_keyed`, `classic_lstm_369_keyed`, and `continuous_multiscale_history`. Require finite losses, exact nesting, correct shapes, and nonzero history gradient by optimizer step three.

- [ ] **Step 3: Run full `R08-NEST`**

Run 30 lockstep epochs on the new split. Require zero mismatch and exactly 43,800 paired confirmation predictions before any candidate full training.

- [ ] **Step 4: Run seed-100 controls and candidate**

Run the classic 256, classic 369, and continuous-history candidate in isolated directories with seed 100 and then run the fixed gate-zero diagnostic.

- [ ] **Step 5: Apply frozen stage-one gates**

Run `analyze_continuous_v08.py`. If any gate fails, do not start seeds 200 or 300. If every gate passes, run all three variants for seeds 200 and 300 and rerun multi-seed analysis.

- [ ] **Step 6: Independently recompute local evidence**

Use a separate verification script or direct pandas/NumPy code that does not import `evaluate_stage1_v08`. Recompute every artifact hash, every basin metric, all paired differences, win fractions, bootstrap interval, date bounds, row counts, and the final gate decision.

- [ ] **Step 7: Write the evidence report**

Separate facts, inference, and unknowns. State the narrow result for the new 60-basin confirmation window; do not claim a 531-basin formal result.

- [ ] **Step 8: Commit frozen results**

Run: `git add src/26_historical_band_experts/registry.csv docs/technical/continuous_multiscale_history_v08.md results/26_historical_band_experts/continuous_multiscale_history_v08 results/26_historical_band_experts/continuous_multiscale_history_v08_smoke && git commit -m "Phase: record continuous multiscale history result"`

### Task 7: Perform independent adversarial audit

**Files:**
- Create: `docs/technical/continuous_multiscale_history_v08_independent_audit.md`
- Modify only if the auditor finds a verified defect: the smallest affected version 08 code, test, result, registry, or report files.

**Interfaces:**
- Consumes: committed version 08 implementation and frozen artifacts.
- Produces: independent `PASS`, `HOLD`, or `REJECT`, with implementation validity separated from predictive success.

- [ ] **Step 1: Dispatch an independent clean-context reviewer**

The reviewer must read the design and handoff, inspect the committed diff, verify the actual model graph and parameters, trace all input reads, recompute bins/splits/hashes/metrics/gates, and actively attempt to falsify the conclusion.

- [ ] **Step 2: Require an evidence-backed audit report**

The report must list exact files, commands, counts, hashes, mismatches, and limitations. It must explicitly check the 1989-10-04 forcing-history caveat and confirm that no formal-evaluation target or answer was accessed.

- [ ] **Step 3: Repair only confirmed defects**

For a confirmed defect, add a failing regression test, make the smallest fix, rerun affected outputs when required, preserve superseded artifacts under a clearly named archive, and ask the same reviewer to re-audit. Do not change model design or gates after seeing performance.

- [ ] **Step 4: Run final verification**

Run: `pytest src/26_historical_band_experts/tests -q`

Expected: all tests pass. Verify `git status --short`, result manifests, and audit verdict.

- [ ] **Step 5: Commit audit closure**

Run: `git add docs/technical/continuous_multiscale_history_v08_independent_audit.md && git commit -m "Phase: record independent continuous history audit"`

