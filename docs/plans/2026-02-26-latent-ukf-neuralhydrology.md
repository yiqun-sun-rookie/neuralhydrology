# Latent-UKF Implementation Plan (Project 03 in kalmannet)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a publishable Latent-UKF data assimilation workflow on top of NeuralHydrology that improves long-lead forecast skill (LT12/LT24), especially under sparse observations.

**Architecture:** Start from a frozen NeuralHydrology recurrent model (GRU/LSTM family), expose hidden states (`h_n`, optional `c_n`), project them to a compact latent state, and run Trainable-UKF updates in latent space using observed discharge as measurement. Decode corrected latent state back to corrected discharge (or corrected hidden state), then evaluate against open-loop and lagged-flow baselines under controlled missing-observation scenarios.

**Tech Stack:** Python, PyTorch, neuralhydrology (pip dependency), pandas, pytest, external `filters` repository (`TrainableUKF`), existing `kalmannet` training logic.

**Host Repository:** `G:/github/pycharm/projects/kalmannet` — as **Project 03: Latent-UKF DA**.

---

## Project Context Within kalmannet

| Project | Model Stack | DA Target | Status |
|:---|:---|:---|:---|
| **01: Regge Hourly DA** | KalmanNet + WALRUS | Physical states (5-dim) | Paper Writing |
| **02: Global Caravan DA** | StaticEncoder + DifferentiableM4 + KalmanNet | Physical states (4-dim) | Development |
| **03: Latent-UKF DA** | Frozen NH RNN + LatentAdapter + TrainableUKF | Learned latent states (8-dim) | **This plan** |

### External Dependencies

| Dependency | How to Access | Notes |
|:---|:---|:---|
| `neuralhydrology` | `pip install -e G:/github/pycharm/projects/neuralhydrology` | Provides base models (CudaLSTM, GRU, EALSTM) and data loaders (CAMELS) |
| `filters` | `PYTHONPATH=F:/github/pycharm/projects/filters` (already in `.env`) | Provides `TrainableUKF`, `BatchUnscentedKalmanFilterGPU`, `MerweScaledSigmaPoints` |

### Directory Layout (New Files)

```
kalmannet/
  src/
    latent_da/                          # Project 03 source code
      __init__.py
      models/
        latent_adapter.py               # Encode/decode hidden ↔ latent
      da/
        ukf_bridge.py                   # TrainableUKF instantiation for latent space
        latent_ukf_runner.py            # Per-timestep encode→predict→update→decode loop
        missingness.py                  # Deterministic observation masks
        io.py                           # NH hidden-state export utilities
      configs/
        latent_ukf_default.yml          # Default latent-UKF config
        experiment_protocol.yml         # Locked experiment contract
      scripts/
        export_hidden_rollout.py        # Extract h_n from frozen NH model
        run_experiment.py               # Single experiment entry point
        run_latent_ukf_grid.py          # Full experiment matrix
        summarize_latent_ukf.py         # Aggregate results + significance tests
      docs/
        LATENT_UKF_PROTOCOL.md          # Experiment protocol
        EXPERIMENT_RESULTS.md           # Results tracking
    shared/                             # Existing shared utilities (metrics, plotting)
  tests/                                # New test root for Project 03+
    conftest.py
    test_latent_da_protocol.py
    test_latent_da_hidden_export.py
    test_latent_da_latent_adapter.py
    test_latent_da_ukf_bridge.py
    test_latent_da_missingness.py
  results/
    latent_da/                          # Experiment outputs
```

---

## Approach Options (Choose One)

### Option A (Recommended): Post-hoc Latent-UKF Adapter
- Keep NeuralHydrology model frozen.
- Add a latent adapter + UKF correction pipeline for inference/evaluation only.
- Pros: Fastest path to paper-grade ablation and clean attribution of gains.
- Cons: Does not improve base model training itself.

### Option B: End-to-End Joint Training
- Train latent projection/decoder and UKF parameters jointly with forecast loss.
- Pros: Potentially highest ceiling.
- Cons: Harder optimization, higher instability, harder to isolate mechanism.

### Option C: Two-Stage Distillation
- Use Option A as teacher, distill corrected trajectories into lightweight student.
- Pros: Better deployment speed, easy runtime story.
- Cons: Extra stage; less direct DA novelty than Option A/B.

**Recommendation:** Start with Option A, finish a complete evidence package, then optionally add a small Option B ablation.

---

### Task 1: Lock Baselines and Experiment Contract

**Files:**
- Create: `src/latent_da/docs/LATENT_UKF_PROTOCOL.md`
- Create: `src/latent_da/docs/EXPERIMENT_RESULTS.md`
- Create: `src/latent_da/configs/experiment_protocol.yml`
- Test: `tests/test_latent_da_protocol.py`

**Step 1: Write the failing test**

```python
def test_protocol_requires_openloop_qshift_latentukf_baselines():
    required = {"open_loop", "qshift", "latent_ukf"}
    assert required.issubset(load_protocol_baselines())
```

**Step 2: Run test to verify it fails**

Run: `pytest tests/test_latent_da_protocol.py -k protocol -v`
Expected: FAIL because protocol parser/docs do not exist.

**Step 3: Write minimal implementation**

- Add a protocol doc with fixed data split, leads (1/6/12/24), seeds, and metrics.
- Add a YAML config defining the experiment contract (baselines, metrics, data splits).
- Add a short parser/helper or static assertion entry in test fixture.

**Step 4: Run test to verify it passes**

Run: `pytest tests/test_latent_da_protocol.py -k protocol -v`
Expected: PASS.

**Step 5: Commit**

```bash
git add src/latent_da/ tests/test_latent_da_protocol.py
git commit -m "feat(latent-da): lock experiment protocol and baseline contract"
```

---

### Task 2: Expose NH Hidden-State Export For DA

**Files:**
- Create: `src/latent_da/scripts/export_hidden_rollout.py`
- Create: `src/latent_da/da/io.py`
- Test: `tests/test_latent_da_hidden_export.py`
- Reference (read-only, external repo): `neuralhydrology/modelzoo/cudalstm.py`, `neuralhydrology/modelzoo/gru.py`, `neuralhydrology/modelzoo/ealstm.py`

**Step 1: Write the failing test**

```python
def test_export_hidden_rollout_contains_time_aligned_hidden_and_obs(tmp_path):
    out = run_hidden_export(tmp_path)
    assert {"date", "qobs", "y_hat_open_loop", "h_n"}.issubset(set(out.columns))
```

**Step 2: Run test to verify it fails**

Run: `pytest tests/test_latent_da_hidden_export.py -v`
Expected: FAIL because exporter does not exist.

**Step 3: Write minimal implementation**

- Implement evaluator wrapper that calls NH's evaluation API and saves:
  - timestamp,
  - open-loop prediction,
  - observed discharge,
  - hidden vector (`h_n`; optional `c_n`).
- Save parquet/csv for deterministic replay.
- Must work with any NH model that exposes hidden states (CudaLSTM, GRU, EALSTM).

**Step 4: Run test to verify it passes**

Run: `pytest tests/test_latent_da_hidden_export.py -v`
Expected: PASS.

**Step 5: Commit**

```bash
git add src/latent_da/scripts/export_hidden_rollout.py src/latent_da/da/io.py tests/test_latent_da_hidden_export.py
git commit -m "feat(latent-da): add hidden-state export pipeline for latent DA"
```

---

### Task 3: Build Latent Adapter (Projection + Reconstruction)

**Files:**
- Create: `src/latent_da/models/latent_adapter.py`
- Create: `src/latent_da/configs/latent_ukf_default.yml`
- Test: `tests/test_latent_da_latent_adapter.py`

**Step 1: Write the failing test**

```python
def test_latent_adapter_roundtrip_shapes():
    adapter = LatentAdapter(hidden_dim=64, latent_dim=8)
    z, aux = adapter.encode(torch.randn(16, 64))
    h_hat = adapter.decode(z, aux)
    assert z.shape == (16, 8)
    assert h_hat.shape == (16, 64)
```

**Step 2: Run test to verify it fails**

Run: `pytest tests/test_latent_da_latent_adapter.py -v`
Expected: FAIL because adapter does not exist.

**Step 3: Write minimal implementation**

- Linear/MLP encoder for hidden-to-latent.
- Decoder for latent-to-hidden or latent-to-discharge-residual.
- Configurable latent dimension and activation.

**Step 4: Run test to verify it passes**

Run: `pytest tests/test_latent_da_latent_adapter.py -v`
Expected: PASS.

**Step 5: Commit**

```bash
git add src/latent_da/models/latent_adapter.py src/latent_da/configs/latent_ukf_default.yml tests/test_latent_da_latent_adapter.py
git commit -m "feat(latent-da): add latent projection/reconstruction adapter"
```

---

### Task 4: Integrate External Trainable-UKF In Latent Space

**Files:**
- Create: `src/latent_da/da/ukf_bridge.py`
- Create: `src/latent_da/da/latent_ukf_runner.py`
- Test: `tests/test_latent_da_ukf_bridge.py`
- Reference (read-only, same repo):
  - `experiments/optimize_hyper_parameters/train_and_eval.py` — `build_trainable_kf()` pattern
- Reference (read-only, external `filters` repo):
  - `filters/adapt_trainable_kf/adaptive_ukf.py`
  - `filters/filter/batch/my_version/batch_unscentedkalmanfilter_gpu.py`

**Step 1: Write the failing test**

```python
def test_ukf_bridge_updates_latent_state_and_returns_covariance():
    out = run_latent_ukf_step(batch_size=4, latent_dim=8)
    assert out["z_post"].shape == (4, 8)
    assert out["P_post"].shape == (4, 8, 8)
```

**Step 2: Run test to verify it fails**

Run: `pytest tests/test_latent_da_ukf_bridge.py -v`
Expected: FAIL because bridge does not exist.

**Step 3: Write minimal implementation**

- Borrow the `build_trainable_kf()` instantiation pattern from `train_and_eval.py:260-337`.
- Replace `fx_walrus_batch`/`hx_walrus_batch` with latent-space equivalents:
  - `fx_latent`: adapter.decode → one-step RNN forward (frozen, `torch.no_grad`) → adapter.encode
  - `hx_latent`: adapter.decode → head → predicted discharge
- Instantiate UKF core with latent `dim_x` and discharge `dim_z=1`.
- Support:
  - `learn_q`, `learn_r` (gradient-based),
  - `adapt_online` (Berry-Mehra branch),
  - covariance stabilization (symmetrize + jitter).
- Lazy import `filters` with explicit error message if missing.

**Step 4: Run test to verify it passes**

Run: `pytest tests/test_latent_da_ukf_bridge.py -v`
Expected: PASS.

**Step 5: Commit**

```bash
git add src/latent_da/da/ukf_bridge.py src/latent_da/da/latent_ukf_runner.py tests/test_latent_da_ukf_bridge.py
git commit -m "feat(latent-da): integrate trainable-ukf latent-state updater"
```

---

### Task 5: Add Missing-Observation Stress Tests

**Files:**
- Create: `src/latent_da/da/missingness.py`
- Create: `tests/test_latent_da_missingness.py`
- Modify: `src/latent_da/scripts/run_experiment.py`

**Step 1: Write the failing test**

```python
def test_missingness_mask_reproducible_for_fixed_seed():
    m1 = make_mask(length=1000, ratio=0.5, seed=42)
    m2 = make_mask(length=1000, ratio=0.5, seed=42)
    assert (m1 == m2).all()
```

**Step 2: Run test to verify it fails**

Run: `pytest tests/test_latent_da_missingness.py -v`
Expected: FAIL because generator does not exist.

**Step 3: Write minimal implementation**

- Implement deterministic masks for 100%, 50%, 25% observation availability.
- Add contiguous-gap mode for realistic outages.
- Wire CLI flags into experiment runner.

**Step 4: Run test to verify it passes**

Run: `pytest tests/test_latent_da_missingness.py -v`
Expected: PASS.

**Step 5: Commit**

```bash
git add src/latent_da/da/missingness.py src/latent_da/scripts/run_experiment.py tests/test_latent_da_missingness.py
git commit -m "feat(latent-da): add sparse-observation stress testing tools"
```

---

### Task 6: Execute Paper Matrix and Summarize Evidence

**Files:**
- Create: `src/latent_da/scripts/run_latent_ukf_grid.py`
- Create: `src/latent_da/scripts/summarize_latent_ukf.py`
- Create: `results/latent_da/latent_ukf_summary.csv`
- Modify: `src/latent_da/docs/EXPERIMENT_RESULTS.md`

**Step 1: Write the failing test**

```python
def test_summary_contains_required_comparisons(tmp_path):
    df = build_latent_ukf_summary(tmp_path)
    assert {"open_loop", "qshift", "latent_ukf"}.issubset(set(df["method"]))
```

**Step 2: Run test to verify it fails**

Run: `pytest tests/ -k summary -v`
Expected: FAIL because summarizer does not exist.

**Step 3: Write minimal implementation**

- Run matrix:
  - leads: 1/6/12/24
  - seeds: 2025/2026/2027
  - obs availability: 100/50/25
  - methods: open-loop, qshift, latent-ukf
- Aggregate NSE/KGE/RMSE/Peak-MAPE + paired significance test.

**Step 4: Run test to verify it passes**

Run: `pytest tests/ -k summary -v`
Expected: PASS.

**Step 5: Commit**

```bash
git add src/latent_da/scripts/run_latent_ukf_grid.py src/latent_da/scripts/summarize_latent_ukf.py src/latent_da/docs/EXPERIMENT_RESULTS.md
git commit -m "feat(latent-da): add experiment grid and summary pipeline"
```

---

## Verification Checklist Before Claiming Success

- Run targeted tests:
  - `pytest tests/test_latent_da_hidden_export.py -v`
  - `pytest tests/test_latent_da_latent_adapter.py -v`
  - `pytest tests/test_latent_da_ukf_bridge.py -v`
  - `pytest tests/test_latent_da_missingness.py -v`
- Run full affected set:
  - `pytest tests/test_latent_da_protocol.py -v`
- Run pilot experiment:
  - `python src/latent_da/scripts/run_latent_ukf_grid.py --lead 24 --seed 2025 --obs-ratio 0.5`
- Confirm summary artifact exists in `results/latent_da/` and includes all baselines.

---

## Code Reuse From Existing kalmannet

| What | Source (read-only reference) | How to Reuse |
|:---|:---|:---|
| UKF instantiation pattern | `experiments/optimize_hyper_parameters/train_and_eval.py:260-337` | Borrow `build_trainable_kf()` flow; replace `fx`/`hx` with latent-space versions |
| Sigma point config | Same file, `MerweScaledSigmaPoints(alpha, beta, kappa)` | Copy pattern, tune alpha for latent space |
| Q/R learning + Berry-Mehra | `filters` repo (external, already on PYTHONPATH) | Direct import, zero modification |
| Covariance stabilization | `train_and_eval.py` symmetrize + jitter | Copy pattern into `ukf_bridge.py` |
| Shared metrics | `src/shared/metrics.py` | Direct import from same repo |

**Do NOT reuse** (incompatible): kalmannet Pipeline/DataLoader classes, WALRUS `fx`/`hx`, legacy `knet/` training loops.

---

## Publication Positioning (How This Avoids Crowded Prior Work)

- Not "just UKF + LSTM":
  - explicit latent-state assimilation on top of a strong open-loop and lagged-flow baseline;
  - adaptive covariance branch (`learn_q/learn_r` and `adapt_online`) under sparse observations;
  - systematic boundary analysis: where weak DA (qshift) fails and latent-UKF still helps.
