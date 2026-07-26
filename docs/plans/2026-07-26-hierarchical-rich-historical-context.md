# Hierarchical Rich Historical Context Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build and internally validate one single-output hydrological model with a classic recent branch, a rich-statistic medium-history branch, and a hierarchical old-history branch.

**Architecture:** Reuse the frozen causal lag intervals and classic training protocol. Add deterministic mean, population-standard-deviation, minimum, and maximum tokens for the two older bands; encode the medium band once and the old band with shared within-year and across-year long short-term memory networks. Compare against frozen classic and late-concatenation references plus a new parameter-matched classic control.

**Tech Stack:** Python, PyTorch, NumPy, pandas, pytest, JSON configuration, atomic CSV/checkpoint manifests.

---

### Task 1: Rich causal historical tokens

**Files:**
- Create: `src/26_historical_band_experts/bands_v05.py`
- Create: `src/26_historical_band_experts/tests/test_bands_v05.py`

**Step 1: Write failing tests**

Test that:

```python
tokens = gather_rich_bands_v05(x, basins, targets)
assert tokens["recent"].shape == (batch, 270, 5)
assert tokens["medium"].shape == (batch, 60, 20)
assert tokens["old"].shape == (batch, 5, 12, 20)
```

For hand-built blocks, assert feature order is:

```python
torch.cat((mean, std_unbiased_false, minimum, maximum), dim=-1)
```

Also assert chronological order, exact lag coverage, no response to future perturbations, finite zero standard deviation for constant input, and rejection before lag 3649.

**Step 2: Run the tests and verify the expected import failure**

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_bands_v05.py -q
```

Expected: failure because `bands_v05` does not exist.

**Step 3: Implement the minimum rich-token extractor**

Reuse `BandSpec`, `fixed_band_specs_v03`, `lag_bin_edges`, `_validate_indices`, and `_gather_daily`. Gather each older raw block directly, compute four statistics after forcing normalization, stack 60 blocks chronologically, and reshape only the old band to `[N, 5, 12, 20]`.

**Step 4: Run focused and existing band tests**

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_bands_v05.py src/26_historical_band_experts/tests/test_bands_v03.py -q
```

Expected: all pass.

**Step 5: Commit**

Commit message: `Feat: add rich causal history tokens`

### Task 2: Hierarchical single-output model

**Files:**
- Create: `src/26_historical_band_experts/models_v05.py`
- Create: `src/26_historical_band_experts/tests/test_models_v05.py`

**Step 1: Write failing model-contract tests**

Require:

```python
assert count_trainable_parameters(build_model_v05("hierarchical_rich_history", 100)) == 455_105
assert count_trainable_parameters(build_model_v05("classic_lstm_320", 100)) == 453_441
```

Test one prediction per sample; a single output field; all recurrent forget biases equal 5; candidate output exactly equals the classic 256 output before training in evaluation mode; classic controls ignore medium and old input; changing static attributes changes the generated historical initial states; historical recurrent weights receive nonzero gradients after the initially zero history-head weights take one optimizer step.

**Step 2: Run and verify the import failure**

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_models_v05.py -q
```

Expected: failure because `models_v05` does not exist.

**Step 3: Implement the model**

Implement:

```python
recent: LSTM(32, 256)
medium_static_state: Linear(27, 128)
medium: LSTM(20, 64)
old_within_static_state: Linear(27, 128)
old_within: LSTM(20, 64)
old_across_static_state: Linear(27, 256)
old_across: LSTM(64, 128)
head: Linear(448, 1)
```

Split each static projection evenly into hidden and cell states. Flatten five years into the batch dimension for the shared within-year encoder, restore `[N, 5, 64]`, then run the across-year encoder. Copy the classic 256 recurrent state and the first 256 output weights; zero the other 192 output weights.

**Step 4: Run focused model tests**

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_models_v05.py src/26_historical_band_experts/tests/test_models_v04.py -q
```

Expected: all pass.

**Step 5: Commit**

Commit message: `Feat: add hierarchical rich history model`

### Task 3: Frozen atomic training runner

**Files:**
- Create: `src/26_historical_band_experts/train_v05.py`
- Create: `src/26_historical_band_experts/tests/test_training_v05.py`

**Step 1: Write failing runner tests**

Freeze family name, model sizes, token statistics, training schedule, evidence hashes, 2-epoch smoke limits, 30-epoch pilot budget, and these variants:

```python
("classic_lstm_256", "classic_lstm_320", "hierarchical_rich_history")
```

Require classics to receive only `recent`; require the candidate to receive `recent`, `medium`, and four-dimensional `old`; verify atomic outputs, saved parameter counts, exact metrics recomputation, no overwrite, and zero raw observed-discharge reads.

**Step 2: Run and verify import failure**

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_training_v05.py -q
```

Expected: failure because `train_v05` does not exist.

**Step 3: Implement by adapting the version 04 runner**

Keep the existing data interface, standardization, loss, optimizer, batching, date split, checkpoint selection, prediction format, manifest hashes, and command-line interface. Replace only model construction and dynamic batch gathering. Do not compute prefix sums because rich standard deviation, minima, and maxima require raw block values.

**Step 4: Run focused runner tests**

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_training_v05.py -q
```

Expected: all pass.

**Step 5: Commit**

Commit message: `Feat: add hierarchical history experiment runner`

### Task 4: Staged result analyzer

**Files:**
- Create: `src/26_historical_band_experts/analyze_v05.py`
- Create: `src/26_historical_band_experts/tests/test_analyze_v05.py`

**Step 1: Write failing analysis tests**

Bind the frozen version 03 reference summary and require seed-100 reference runs for classic 256 and late concatenation. Require new candidate and classic 320 runs. Assert exact first-stage gates:

```python
median(candidate - classic256) >= 0.01
median(candidate - classic320) > 0
median(candidate - late_concat) > 0
mean(candidate > classic256) >= 0.55
```

If any gate fails, status must be `complete_stage1_no_go` and no conditional runs may be requested. If all gates pass, request only candidate and classic 320 for seeds 200 and 300, while reusing frozen classic 256 and late-concatenation references from version 04.

**Step 2: Run and verify import failure**

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_analyze_v05.py -q
```

Expected: failure because `analyze_v05` does not exist.

**Step 3: Implement atomic recomputation**

Validate manifests, prediction keys, dates, observed targets, and saved per-basin metrics. Recompute all efficiency coefficients from prediction files. Write `per_seed.csv`, `paired_per_basin.csv`, and `summary.json` atomically.

**Step 4: Run analyzer tests**

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_analyze_v05.py -q
```

Expected: all pass.

**Step 5: Commit**

Commit message: `Feat: add hierarchical history staged analysis`

### Task 5: Freeze configurations and registry

**Files:**
- Create: `src/26_historical_band_experts/configs/smoke_v05.json`
- Create: `src/26_historical_band_experts/configs/pilot_v05.json`
- Modify: `src/26_historical_band_experts/registry.csv`

**Step 1: Add tracked-config tests before configuration files**

Add tests requiring exact binding to design commit `f73ee95281da2b78ecefddaeb819f3e40c751eed`, the existing basin-list hash, target-bundle hash, version 03 summary hash, and version 04 summary hash.

**Step 2: Run and verify missing-config failures**

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_training_v05.py -q
```

Expected: failures for missing `smoke_v05.json` and `pilot_v05.json`.

**Step 3: Add immutable configuration snapshots**

Use result root:

```text
results/26_historical_band_experts/hierarchical_rich_historical_context_v05
```

Smoke: six frozen basins, two epochs, one batch per epoch, eight validation samples. Pilot: sixty frozen basins, thirty epochs, unlimited batches and validation samples.

Add one registry row with status `planned_internal`.

**Step 4: Validate configs and the full local suite**

Run:

```powershell
pytest src/26_historical_band_experts/tests -q
```

Expected: all pass with only the known pre-existing Pytest configuration warning.

**Step 5: Commit**

Commit message: `Phase: freeze hierarchical history pilot`

### Task 6: Smoke run and seed-100 internal screen

**Files:**
- Outputs: `results/26_historical_band_experts/hierarchical_rich_historical_context_v05/`

**Step 1: Check resources and protected state**

Confirm no competing training process, sufficient graphics-memory headroom, clean branch, unchanged frozen hashes, and absence of the new output directories.

**Step 2: Run all smoke variants**

Run the smoke configuration for classic 256, classic 320, and hierarchical rich history on the available graphics processor. Analyze their artifacts and confirm no temporary files, nonfinite metrics, forbidden reads, or date leakage.

**Step 3: Run the two new full seed-100 jobs**

Reuse frozen version 03 classic 256 and late-concatenation predictions. Train only:

```text
classic_lstm_320_s100
hierarchical_rich_history_s100
```

**Step 4: Analyze first-stage gates**

Run `analyze_v05.py` and stop if status is `complete_stage1_no_go`. Run seeds 200 and 300 only if status requests conditional runs.

### Task 7: Independent verification and result record

**Files:**
- Create: `docs/technical/hierarchical_rich_historical_context_v05.md`
- Modify: `src/26_historical_band_experts/registry.csv`

**Step 1: Recompute evidence independently**

Run every version 05 test plus the full idea-local suite. Recompute metrics from predictions, verify file hashes and manifests, check run counts and prediction-row counts, scan source and artifacts for forbidden paths and formal-evaluation dates, and confirm Git diff/status.

**Step 2: Record only supported conclusions**

Write the exact per-seed metrics, paired medians, win fraction, gate decisions, artifact hashes, dates, limitations, and explicit statement that the sealed 531-basin formal benchmark was not run.

**Step 3: Run final verification**

Run:

```powershell
pytest src/26_historical_band_experts/tests -q
git diff --check
git status --short
```

Expected: all tests pass, no whitespace errors, and only intended result-record changes remain.

**Step 4: Commit**

Commit message: `Phase: record hierarchical rich history result`
