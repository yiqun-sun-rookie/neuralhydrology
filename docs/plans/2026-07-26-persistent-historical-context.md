# Persistent Historical Context Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Confirm the existing single-head late-concatenation signal across three seeds and test two stronger single-output mechanisms for using disjoint medium and old forcing history.

**Architecture:** Reuse the frozen version 03 data bands, classic training schedule, trusted target bundle, and immutable seed-100 reference artifacts. Add one model that repeats an 8-dimensional historical context at every recent timestep and one model that adds a recent-conditioned historical residual before the original single flow head. Compare every candidate with the exact classic Long Short-Term Memory model, a within-1% parameter-count control, and the equal-information late-concatenation model.

**Tech Stack:** Python 3, PyTorch, NumPy, pandas, pytest, existing CAMELS-US pilot data loader.

---

### Task 1: Freeze model contracts with failing tests

**Files:**
- Create: `src/26_historical_band_experts/tests/test_models_v04.py`
- Create: `src/26_historical_band_experts/models_v04.py`

**Step 1: Write the failing parameter-count and output-contract tests**

Test the exact counts:

```python
EXPECTED_PARAMETERS = {
    "classic_lstm_256": 297_217,
    "classic_lstm_261": 308_242,
    "classic_lstm_265": 317_206,
    "classic_lstm_270": 328_591,
    "late_concat": 308_401,
    "persistent_context": 316_937,
    "recent_conditioned_residual": 327_617,
}
```

For every variant, assert one `prediction` tensor of shape `[batch]`, forget-gate bias 5 in every recurrent module, and less than 1% parameter-count difference between each new candidate and its matched classic control.

**Step 2: Run the test and verify the missing module fails**

Run:

`pytest src/26_historical_band_experts/tests/test_models_v04.py -q`

Expected: collection fails because `models_v04` does not exist.

**Step 3: Implement the minimal model classes**

Create:

- `PersistentContextLSTM`: two 24-unit historical encoders, `Linear(48, 8)`, repeat the 8 values over 270 recent steps, a 40-input/256-unit recent Long Short-Term Memory layer, and one `Linear(256, 1)` head;
- `RecentConditionedResidualLSTM`: two 24-unit historical encoders, `Linear(48, 32)`, `Linear(288, 32)` sigmoid gate, zero-initialized `Linear(32, 256)` residual projection, the classic 256-unit recent backbone, and the original one-output head;
- `build_model_v04`: deterministic factory for the seven frozen variants.

Reuse `ClassicLSTM`, `LateConcatHistoricalLSTM`, `ModelOutput`, `count_trainable_parameters`, `_append_statics`, and `_set_forget_bias` from `models_v03.py`.

**Step 4: Run the model tests**

Run:

`pytest src/26_historical_band_experts/tests/test_models_v04.py -q`

Expected: all tests pass.

**Step 5: Add initialization-equivalence and gradient-path tests**

Assert:

- both new candidates equal the same seeded exact classic model bit-for-bit in evaluation mode at initialization;
- changing medium or old inputs cannot affect the classic controls;
- after one neutral-connector update, both historical encoders receive nonzero gradients through the single output.

Run the test before implementation changes when a behavior is not yet present, observe the intended failure, then implement only the missing behavior and rerun.

**Step 6: Commit**

```powershell
git add src/26_historical_band_experts/models_v04.py src/26_historical_band_experts/tests/test_models_v04.py
git commit -m "Feat: add persistent historical context models"
```

### Task 2: Add the immutable version 04 runner

**Files:**
- Create: `src/26_historical_band_experts/tests/test_training_v04.py`
- Create: `src/26_historical_band_experts/train_v04.py`

**Step 1: Write failing runner tests**

Cover:

- exact classic schedule at epochs 1, 11, 12, 21, 22, and 30;
- only classic controls receive the recent band, while the three historical candidates receive recent, medium, and old bands;
- every variant writes exactly `config.json`, `checkpoint.pt`, `predictions.csv`, `per_basin_metrics.csv`, and `manifest.json`;
- saved metrics equal a fresh recomputation from daily predictions;
- an existing nonempty directory is never overwritten;
- pilot mode requires 30 complete epochs and no sample limits;
- the basin list and trusted target bundle hashes are mandatory and validated;
- the manifest records zero raw observed-discharge reads, target-bundle use, actual parameter count, optimizer steps, epoch learning rates, artifact hashes, and the frozen design commit.

**Step 2: Run and observe failure**

Run:

`pytest src/26_historical_band_experts/tests/test_training_v04.py -q`

Expected: collection fails because `train_v04` does not exist.

**Step 3: Implement the runner**

Adapt the proven version 03 atomic runner without changing the optimizer, loss, batch generation, normalization, evaluation, or checkpoint policy. Import `gather_fixed_bands_v03` and `forcing_prefix` so the historical intervals remain byte-for-byte defined by the version 03 implementation.

The command-line interface is:

```powershell
python src/26_historical_band_experts/train_v04.py `
  --config <config.json> `
  --variant <variant> `
  --seed <seed> `
  --data-dir data/camels_us `
  --targets-file results/26_historical_band_experts/trusted_targets/pilot_targets_1999_2008_v02.csv `
  --targets-sha256 d4c93675eefd433515d6f7e10943caea31c6eb7e30533d4c387cf9325886e05c `
  --device cuda
```

**Step 4: Run the runner tests**

Run:

`pytest src/26_historical_band_experts/tests/test_training_v04.py -q`

Expected: all tests pass.

**Step 5: Commit**

```powershell
git add src/26_historical_band_experts/train_v04.py src/26_historical_band_experts/tests/test_training_v04.py
git commit -m "Feat: add persistent context experiment runner"
```

### Task 3: Implement the frozen staged analysis

**Files:**
- Create: `src/26_historical_band_experts/tests/test_analyze_v04.py`
- Create: `src/26_historical_band_experts/analyze_v04.py`

**Step 1: Write failing decision-rule tests**

Test two distinct frozen rules:

1. late-concatenation confirmation uses three-seed mean paired effects per basin and the five criteria from version 03;
2. new-candidate screening additionally requires a positive paired median against late concatenation;
3. new-candidate three-seed confirmation additionally requires a positive three-seed mean paired median against late concatenation.

Test exact conditional-run generation: exact classic and late concatenation are reused; only a passing new candidate and its matched control are added for seeds 200 and 300.

**Step 2: Run and observe failure**

Run:

`pytest src/26_historical_band_experts/tests/test_analyze_v04.py -q`

Expected: collection fails because `analyze_v04` does not exist.

**Step 3: Implement artifact validation and staged analysis**

The analyzer must:

- load version 03 seed-100 `classic_lstm_256`, `classic_lstm_261`, and `late_concat` from the immutable version 03 result root;
- load all new runs from the version 04 root;
- validate run identity, exact parameter count, 60 basins, 731 validation days per basin, finite values, no duplicate keys, matching observations, raw-discharge-read ledger, and every artifact hash;
- recompute all per-basin scores from daily predictions;
- emit `per_seed.csv`, `paired_per_basin.csv`, and `summary.json` atomically;
- report late-concatenation confirmation independently from the two new-model decisions;
- never infer paired effects by subtracting absolute medians.

**Step 4: Run the analyzer tests**

Run:

`pytest src/26_historical_band_experts/tests/test_analyze_v04.py -q`

Expected: all tests pass.

**Step 5: Commit**

```powershell
git add src/26_historical_band_experts/analyze_v04.py src/26_historical_band_experts/tests/test_analyze_v04.py
git commit -m "Feat: add persistent context staged analysis"
```

### Task 4: Freeze configs and experiment registry

**Files:**
- Create: `src/26_historical_band_experts/configs/smoke_v04.json`
- Create: `src/26_historical_band_experts/configs/pilot_v04.json`
- Modify: `src/26_historical_band_experts/registry.csv`

**Step 1: Create immutable configs**

Both configs must include:

- `experiment_family`: `persistent_historical_context_v04`;
- the existing 60-basin file and SHA-256;
- trusted target bundle SHA-256 `d4c93675eefd433515d6f7e10943caea31c6eb7e30533d4c387cf9325886e05c`;
- version 03 reference result root and summary SHA-256 `8b5d2469fb36c074ccc5d621095571d1099092eb46179022829632b8ca49f4d0`;
- the committed version 04 design commit;
- hidden widths 256, 24, 8, and 32;
- the exact classic schedule and output root.

Smoke mode uses 2 epochs, 2 optimizer batches per epoch, and a small balanced validation subset. Pilot mode uses 30 epochs and no limits.

**Step 2: Add one registry row**

Use one experiment identity, one base config, one isolated output root, staged seed policy, and state `planned`.

**Step 3: Validate configs**

Run:

`pytest src/26_historical_band_experts/tests/test_training_v04.py src/26_historical_band_experts/tests/test_analyze_v04.py -q`

Expected: all tests pass and both config files are accepted.

**Step 4: Commit**

```powershell
git add src/26_historical_band_experts/configs/smoke_v04.json src/26_historical_band_experts/configs/pilot_v04.json src/26_historical_band_experts/registry.csv
git commit -m "Phase: freeze persistent context pilot"
```

### Task 5: Run code smoke tests

**Files:**
- Create only ignored run directories under `results/26_historical_band_experts/persistent_historical_context_v04_smoke/`

**Step 1: Check resources without changing other processes**

Run:

`nvidia-smi --query-gpu=memory.total,memory.used,memory.free,utilization.gpu --format=csv,noheader,nounits`

Do not terminate unrelated jobs. Start a run only when at least 8 gigabytes of graphics memory is free.

**Step 2: Run all seven smoke arms**

Run the version 04 runner once per variant with seed 100 and the smoke config. Every output directory must be new.

**Step 3: Verify smoke evidence**

Run:

`pytest src/26_historical_band_experts/tests -q`

Then independently read every smoke manifest, verify hashes, parameter counts, one-output predictions, optimizer steps, and finite metrics.

Expected: no failing tests and seven complete smoke runs. The pre-existing pytest configuration warning may remain and must be reported rather than hidden.

### Task 6: Run the ten required full pilot arms

**Files:**
- Create only ignored run directories under `results/26_historical_band_experts/persistent_historical_context_v04/`

**Step 1: Confirm immutable inputs**

Verify the basin file, trusted target bundle, version 03 summary, and three reused seed-100 reference manifests against their recorded SHA-256 values.

**Step 2: Run late-concatenation confirmation**

Run these six arms serially on the graphics processor, checking free memory before each:

```text
classic_lstm_256_s200
classic_lstm_261_s200
late_concat_s200
classic_lstm_256_s300
classic_lstm_261_s300
late_concat_s300
```

Use an outer command timeout of at least 1,200 seconds per arm. Preserve any incomplete attempt in a timestamped directory and never overwrite it.

**Step 3: Run new-candidate screening**

Run:

```text
classic_lstm_265_s100
persistent_context_s100
classic_lstm_270_s100
recent_conditioned_residual_s100
```

**Step 4: Analyze the first complete matrix**

Run:

`python src/26_historical_band_experts/analyze_v04.py --config src/26_historical_band_experts/configs/pilot_v04.json`

Read `summary.json`. This is the only authorization for conditional model runs.

### Task 7: Run only conditionally authorized seeds

**Files:**
- Create only analyzer-requested run directories under the version 04 result root.

**Step 1: Read the exact required-run list**

If neither new candidate passes the four frozen seed-100 criteria, run nothing more.

If one or both pass, run only each passing candidate and its matched control for seeds 200 and 300. Reuse the already completed exact classic and late-concatenation runs.

**Step 2: Re-run staged analysis**

Run the analyzer after all requested directories are complete. Do not modify thresholds or inspect the sealed formal evaluation period.

### Task 8: Independently verify and record the result

**Files:**
- Create: `docs/technical/persistent_historical_context_v04.md`
- Modify: `src/26_historical_band_experts/registry.csv`

**Step 1: Recompute evidence independently**

Using a read-only verification command separate from the analyzer:

- enumerate every expected physical artifact;
- recompute SHA-256 values;
- reload every daily prediction row;
- verify identical basin-date keys and observations;
- recompute every per-basin score;
- recompute all frozen paired medians, win fractions, positive-seed counts, and bootstrap intervals;
- confirm prediction dates are only 2006-10-01 through 2008-09-30;
- scan version 04 code paths for forbidden raw discharge or sealed-answer names.

**Step 2: Run final tests**

Run:

`pytest src/26_historical_band_experts/tests -q`

Expected: zero failures.

Run:

`git diff --check`

Expected: exit code 0.

**Step 3: Write the result record**

State fact, interpretation, and unknown separately. Include exact absolute medians, paired effects, uncertainty intervals, all frozen gate outcomes, run counts, prediction-row counts, hashes, limitations, and whether any candidate earned a 531-basin formal follow-up.

Do not call an internal validation result a formal benchmark win and do not describe lag bands as measured water age.

**Step 4: Update the registry and commit**

```powershell
git add docs/technical/persistent_historical_context_v04.md src/26_historical_band_experts/registry.csv
git commit -m "Phase: record persistent historical context result"
```
