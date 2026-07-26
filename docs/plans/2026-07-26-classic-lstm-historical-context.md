# Classic LSTM Historical Context Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build and run a traceable 60-basin internal comparison between the classic 256-unit hydrology Long Short-Term Memory network and two single-output extensions that use disjoint medium- and old-history forcing.

**Architecture:** Preserve all version 01 and version 02 code and evidence. Add version 03 modules beside them. The recent branch exactly mirrors the classic 270-day network; two 24-unit encoders read pooled, non-overlapping older bands and contribute either at the single output head or through the recent network's initial memory state.

**Tech Stack:** Python 3, PyTorch, NumPy, pandas, pytest, the repository's CAMELS-US loader, JSON and comma-separated evidence artifacts.

---

### Task 1: Implement the frozen version 03 lag bands

**Files:**
- Create: `src/26_historical_band_experts/bands_v03.py`
- Create: `src/26_historical_band_experts/tests/test_bands_v03.py`

**Step 1: Write the failing tests**

Test that `fixed_band_specs_v03()` returns:

```python
(
    BandSpec("recent", 0, 269, 270),
    BandSpec("medium", 270, 1824, 60),
    BandSpec("old", 1825, 3649, 60),
)
```

Add tests proving every lag from 0 through 3649 occurs exactly once, all gathered values are causal and chronological, pooled constant inputs remain constant, and targets before lag 3649 are rejected.

**Step 2: Run tests to verify RED**

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_bands_v03.py -q
```

Expected: collection fails because `bands_v03` does not exist.

**Step 3: Write the minimal implementation**

Implement `BandSpec`, `fixed_band_specs_v03`, `lag_bin_edges`, `forcing_prefix`, and `gather_fixed_bands_v03`. Reuse the proven prefix-sum algorithm from version 02, changing only the frozen boundaries.

**Step 4: Run tests to verify GREEN**

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_bands_v03.py -q
```

Expected: all version 03 band tests pass.

**Step 5: Commit**

```powershell
git add src/26_historical_band_experts/bands_v03.py src/26_historical_band_experts/tests/test_bands_v03.py
git commit -m "Feat: add classic LSTM historical bands"
```

### Task 2: Implement the five single-output model arms

**Files:**
- Create: `src/26_historical_band_experts/models_v03.py`
- Create: `src/26_historical_band_experts/tests/test_models_v03.py`

**Step 1: Write the failing tests**

Define tests for:

- `ClassicLSTM(hidden_size=256)` has exactly 297,217 trainable parameters;
- widened controls with widths 261 and 266 have 308,242 and 319,467 parameters;
- the forget-gate portion of every recurrent hidden bias equals 5;
- every arm returns exactly one prediction per sample and has no expert-prediction or mixture-weight output;
- `LateConcatHistoricalLSTM` has 308,401 parameters;
- `InitialMemoryHistoricalLSTM` has 320,897 parameters;
- each candidate differs from its capacity control by less than 1%;
- after copying the same classic state, both candidates equal the classic prediction element-by-element in evaluation mode;
- after the zero connector receives one optimizer update, a second backward pass gives nonzero gradients to both historical encoders.

Use a public model factory contract:

```python
model = build_model_v03(variant="late_concat", seed=100)
output = model(dynamic, statics)
assert output.prediction.shape == (batch_size,)
```

**Step 2: Run tests to verify RED**

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_models_v03.py -q
```

Expected: collection fails because `models_v03` does not exist.

**Step 3: Write the minimal implementation**

Implement:

- `ModelOutput`;
- `ClassicLSTM`;
- `LateConcatHistoricalLSTM`;
- `InitialMemoryHistoricalLSTM`;
- `build_model_v03`;
- parameter counting and classic-state copy helpers.

Instantiate a seeded 256-unit classic reference first. Return it for the exact baseline; copy its recent recurrent state and head into each historical candidate. For late concatenation, copy the classic head into columns 0–255 and set columns 256–303 to zero. For initial-memory injection, zero the complete history-to-memory map. Keep one regression output only.

**Step 4: Run tests to verify GREEN**

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_models_v03.py -q
```

Expected: all model tests pass.

**Step 5: Commit**

```powershell
git add src/26_historical_band_experts/models_v03.py src/26_historical_band_experts/tests/test_models_v03.py
git commit -m "Feat: add single-output historical context models"
```

### Task 3: Implement the classic training schedule and atomic runner

**Files:**
- Create: `src/26_historical_band_experts/train_v03.py`
- Create: `src/26_historical_band_experts/tests/test_training_v03.py`

**Step 1: Write the failing tests**

Test:

- the learning rate is 0.001 for epochs 1–11, 0.0005 for epochs 12–21, and 0.0001 for epochs 22–30;
- the exact and widened classic models receive only the recent 270-day tensor;
- both historical candidates receive recent, medium, and old tensors;
- the runner rejects an unknown variant, an output directory containing files, a basin-list hash mismatch, a target-bundle hash mismatch, or a configuration that changes frozen architecture or training values;
- a tiny synthetic run writes `config.json`, `checkpoint.pt`, `predictions.csv`, `per_basin_metrics.csv`, and `manifest.json`;
- the manifest records variant, seed, parameter count, epoch learning rates, optimizer steps, hashes, and zero raw observed-discharge reads.

**Step 2: Run tests to verify RED**

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_training_v03.py -q
```

Expected: collection fails because `train_v03` does not exist.

**Step 3: Write the minimal implementation**

Reuse the version 02 target-only `DataPack`, normalization, metric, atomic-write, and hash functions. Add a frozen configuration validator and a `learning_rate_for_epoch()` function. Train each arm with the same balanced sample order, variance-weighted squared error, Adam, and gradient clipping. Save the final epoch only.

**Step 4: Run tests to verify GREEN**

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_training_v03.py -q
```

Expected: all training tests pass.

**Step 5: Run the complete idea-local regression suite**

Run:

```powershell
pytest src/26_historical_band_experts/tests -q
```

Expected: all old and new tests pass; version 01 and version 02 behavior is unchanged.

**Step 6: Commit**

```powershell
git add src/26_historical_band_experts/train_v03.py src/26_historical_band_experts/tests/test_training_v03.py
git commit -m "Feat: add classic-schedule historical context runner"
```

### Task 4: Freeze experiment configurations and registry identities

**Files:**
- Create: `src/26_historical_band_experts/configs/smoke_v03.json`
- Create: `src/26_historical_band_experts/configs/pilot_v03.json`
- Modify: `src/26_historical_band_experts/registry.csv`

**Step 1: Create immutable configurations**

Both configurations must include:

```json
{
  "experiment_family": "classic_lstm_historical_context_v03",
  "epochs": 30,
  "batch_size": 256,
  "learning_rate_schedule": {"1": 0.001, "12": 0.0005, "22": 0.0001},
  "gradient_clip": 1.0,
  "recent_hidden_size": 256,
  "history_hidden_size": 24,
  "initial_forget_bias": 5.0,
  "output_dropout": 0.4
}
```

The smoke configuration overrides only basin file, result root, epoch count, batch limits, and validation sample limit. The pilot configuration uses the frozen 60-basin list, 30 epochs, no batch limit, no validation limit, and the already frozen target-bundle and basin-list hashes.

**Step 2: Add one registry row**

Register the family with variants:

`classic_lstm_256;classic_lstm_261;classic_lstm_266;late_concat;initial_memory`

Set status to `planned`, seeds to `100;conditional:200;300`, and use a new result root.

**Step 3: Validate JSON and frozen hashes**

Run:

```powershell
python -m json.tool src/26_historical_band_experts/configs/smoke_v03.json
python -m json.tool src/26_historical_band_experts/configs/pilot_v03.json
python -c "import hashlib,pathlib; p=pathlib.Path('src/26_historical_band_experts/configs/pilot_basins_60.txt'); print(hashlib.sha256(p.read_bytes()).hexdigest())"
```

Expected: both JSON files parse and the basin hash equals the configured value.

**Step 4: Commit**

```powershell
git add src/26_historical_band_experts/configs/smoke_v03.json src/26_historical_band_experts/configs/pilot_v03.json src/26_historical_band_experts/registry.csv
git commit -m "Phase: freeze classic historical context pilot"
```

### Task 5: Implement strict analysis and staged gates

**Files:**
- Create: `src/26_historical_band_experts/analyze_v03.py`
- Create: `src/26_historical_band_experts/tests/test_analyze_v03.py`

**Step 1: Write the failing tests**

Test that the analyzer:

- rejects missing runs, wrong variants or seeds, duplicate keys, nonfinite predictions, date-range changes, observation mismatches, bad hashes, and wrong parameter counts;
- independently recomputes per-basin scores from predictions;
- reports paired median differences, basin win fractions, and basin-paired bootstrap confidence intervals;
- applies the frozen one-seed screening rules separately to both candidates;
- emits an exact conditional seed-200/300 run list;
- applies the frozen three-seed continuation rules without silently weakening them.

**Step 2: Run tests to verify RED**

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_analyze_v03.py -q
```

Expected: collection fails because `analyze_v03` does not exist.

**Step 3: Write the minimal implementation**

Use prediction files rather than saved metric summaries as the score source. Make incomplete or inconsistent evidence an error, never a pass. Write `summary.json` atomically.

**Step 4: Run tests to verify GREEN**

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_analyze_v03.py -q
```

Expected: all analyzer tests pass.

**Step 5: Commit**

```powershell
git add src/26_historical_band_experts/analyze_v03.py src/26_historical_band_experts/tests/test_analyze_v03.py
git commit -m "Feat: add staged historical context analysis"
```

### Task 6: Run and verify the six-basin smoke matrix

**Files:**
- Output only: `results/26_historical_band_experts/classic_lstm_historical_context_v03_smoke/`

**Step 1: Confirm resource safety**

Inspect graphics-processor memory, existing Python processes, disk free space, and confirm that no command will reuse an existing result directory.

**Step 2: Run all five smoke arms**

For each variant at seed 100, run:

```powershell
python src/26_historical_band_experts/train_v03.py --config src/26_historical_band_experts/configs/smoke_v03.json --variant <variant> --seed 100 --data-dir data/camels_us --targets-file results/26_historical_band_experts/trusted_targets/pilot_targets_1999_2008_v02.csv --targets-sha256 d4c93675eefd433515d6f7e10943caea31c6eb7e30533d4c387cf9325886e05c --device <safe_device>
```

**Step 3: Verify smoke evidence**

Check all five manifests, hashes, prediction counts, date bounds, finite scores, and zero raw observed-discharge reads. Do not interpret smoke scores as model effectiveness.

### Task 7: Run the seed-100 60-basin structure screen

**Files:**
- Output only: `results/26_historical_band_experts/classic_lstm_historical_context_v03/`

**Step 1: Run all five frozen arms**

Use `pilot_v03.json`, seed 100, and the same trusted target bundle. Run serially on a safe device so the existing user process is not disturbed.

**Step 2: Verify each run immediately**

After each run, verify its exit code, manifest status, parameter count, prediction count, date bounds, and artifact hashes.

**Step 3: Compute the frozen first-stage gate**

Run `analyze_v03.py` for seed 100. Record the two candidate comparisons against both the exact classic model and the corresponding capacity control.

**Step 4: Apply the stopping rule**

If neither candidate passes all three frozen screening criteria, set the experiment status to `no_go_stage1`, write the result record, and do not run seeds 200 or 300.

If at least one candidate passes, run only the additional models listed by the analyzer.

### Task 8: Conditionally run seeds 200 and 300

**Files:**
- Output only under the version 03 pilot result root.

**Step 1: Run the exact conditional matrix**

For each passing candidate, run seed 200 and seed 300 for:

- `classic_lstm_256`;
- that candidate;
- its matching widened classic control.

Deduplicate shared baseline runs. Do not add architectures or change boundaries.

**Step 2: Verify every run**

Check completion, hashes, configuration identity, prediction coverage, and parameter counts.

**Step 3: Apply the three-seed continuation gate**

Recompute all scores from predictions and write the final `summary.json`. Status is `go_internal` only if all five frozen continuation criteria pass; otherwise status is `no_go_multiseed`.

### Task 9: Record, audit, and verify the conclusion

**Files:**
- Create: `docs/technical/classic_lstm_historical_context_v03.md`
- Modify: `src/26_historical_band_experts/registry.csv`

**Step 1: Write the evidence record**

Record:

- source commit;
- configuration and target-bundle hashes;
- executed and skipped runs;
- actual parameter counts;
- prediction and basin counts;
- absolute median scores;
- all paired comparisons and confidence intervals;
- stage decision;
- explicit limits: internal 60-basin validation, previously exposed validation period, no formal 531-basin score, no physical water-age claim.

**Step 2: Run fresh verification**

Run:

```powershell
pytest src/26_historical_band_experts/tests -q
git diff --check
git status --short
```

Rerun the analyzer from the persisted prediction files and compare its output hash with the recorded summary.

**Step 3: Inspect the implementation independently**

Review the complete diff against the design checklist. Specifically search for:

- more than one flow output;
- any gate or expert-flow mixture;
- overlapping or future lag indices;
- raw observed-discharge file reads in candidate code;
- deviations from the classic training schedule;
- overwritten version 01 or version 02 evidence.

**Step 4: Commit**

```powershell
git add docs/technical/classic_lstm_historical_context_v03.md src/26_historical_band_experts/registry.csv
git commit -m "Phase: record classic historical context result"
```

**Step 5: Final verification before any completion claim**

Run the complete idea-local tests again, rerun the analyzer, verify the final Git status, and report only conclusions supported by the fresh outputs.
