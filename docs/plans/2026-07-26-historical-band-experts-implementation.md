# Fixed Historical-Band Experts Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build and run a sealed small-sample comparison of a mainstream Long Short-Term Memory network, an equal-input multiscale fusion model, and explicit fixed historical-band experts.

**Architecture:** All experiment code lives in `src/26_historical_band_experts/` and does not modify the packaged `neuralhydrology/` code or `src/fair_benchmark/`. A shared causal batch builder exposes exactly three disjoint lag bands; two equal-input models share the same encoders, while the expert model adds expert-specific heads and a dynamic softmax gate.

**Tech Stack:** Python 3.11, PyTorch, NumPy, pandas, pytest, the existing NeuralHydrology CAMELS-US loaders.

---

## Fixed constraints

- Do not read formal evaluation-period discharge from 1989-10-01 through 1999-09-30.
- Do not modify `src/fair_benchmark/`, frozen artifacts, or the user's original dirty checkout.
- Record that the pre-implementation `pytest --smoke-test` run collected 873 tests, timed out after 120 seconds at 54%, and already contained unrelated failures.
- Treat only the new isolated test suite plus named relevant tests as the implementation gate.
- Use experiment identifiers `mainstream_lstm`, `multiscale_fusion`, and `historical_band_experts`; seeds are 100, 200, and 300.
- Never tune boundaries, basin list, seeds, or stopping criteria after viewing validation results.

### Task 1: Causal historical-band extraction

**Files:**
- Create: `src/26_historical_band_experts/__init__.py`
- Create: `src/26_historical_band_experts/bands.py`
- Create: `src/26_historical_band_experts/tests/test_bands.py`

**Step 1: Write failing tests**

Test exact coverage:

```python
def test_fixed_bands_are_disjoint_complete_and_causal():
    specs = fixed_band_specs()
    covered = np.concatenate([np.arange(s.start_lag, s.end_lag + 1) for s in specs])
    assert covered.min() == 0
    assert covered.max() == 3649
    assert len(covered) == 3650
    assert len(np.unique(covered)) == 3650
```

Test chronology and pooled means using a synthetic sequence whose value equals its time index. Test that changing any future value leaves all extracted inputs unchanged.

**Step 2: Run tests and confirm red**

Run:

`pytest src/26_historical_band_experts/tests/test_bands.py -v`

Expected: import failure because `bands.py` does not exist.

**Step 3: Implement the minimum batch builder**

Implement:

```python
@dataclass(frozen=True)
class BandSpec:
    name: str
    start_lag: int
    end_lag: int
    bins: int

def fixed_band_specs() -> tuple[BandSpec, ...]:
    return (
        BandSpec("recent", 0, 29, 30),
        BandSpec("medium", 30, 1824, 60),
        BandSpec("old", 1825, 3649, 60),
    )
```

Use direct chronological gathering for the recent band and cumulative-sum interval means for the medium and old bands. Accept tensors `x[B,T,D]`, basin indices, and target indices; return tensors shaped `[N,30,D]`, `[N,60,D]`, and `[N,60,D]`.

**Step 4: Run tests and confirm green**

Run:

`pytest src/26_historical_band_experts/tests/test_bands.py -v`

Expected: all tests pass.

**Step 5: Commit**

```powershell
git add src/26_historical_band_experts/__init__.py src/26_historical_band_experts/bands.py src/26_historical_band_experts/tests/test_bands.py
git commit -m "Feat: add causal historical-band extraction"
```

### Task 2: Three parameter-matched model arms

**Files:**
- Create: `src/26_historical_band_experts/models.py`
- Create: `src/26_historical_band_experts/tests/test_models.py`

**Step 1: Write failing tests**

Cover:

- all three models return `prediction[N]`;
- expert model returns `weights[N,3]`;
- every weight is nonnegative and each row sums to one within `1e-6`;
- backpropagation reaches all three expert encoders, all three heads, and the gate;
- parameter counts of all arms differ by no more than 2%;
- multiscale fusion and expert models accept exactly the same tensors.

**Step 2: Run tests and confirm red**

`pytest src/26_historical_band_experts/tests/test_models.py -v`

Expected: import failure because `models.py` does not exist.

**Step 3: Implement the models**

Implement:

- `MainstreamLSTM`: 270 daily steps, five dynamic inputs plus 27 repeated static inputs, hidden width 128;
- `MultiscaleFusion`: three hidden-width-64 encoders, concatenate three states, current forcing, and statics, then `Linear(224,32) -> ReLU -> Linear(32,1)`;
- `HistoricalBandExperts`: the same three encoders, three `Linear(64,1)` expert heads, and `Linear(224,32) -> ReLU -> Linear(32,3) -> Softmax` gate.

Use the same output dropout value in all arms. Initialize the Long Short-Term Memory forget-gate bias to 5 to match the repository's mainstream baseline.

**Step 4: Run tests and confirm green**

`pytest src/26_historical_band_experts/tests/test_models.py -v`

Expected: all tests pass and measured parameter-count spread is at most 2%.

**Step 5: Commit**

```powershell
git add src/26_historical_band_experts/models.py src/26_historical_band_experts/tests/test_models.py
git commit -m "Feat: add matched historical-band model arms"
```

### Task 3: Allowed-data loader and frozen basin selection

**Files:**
- Create: `src/26_historical_band_experts/data.py`
- Create: `src/26_historical_band_experts/select_basins.py`
- Create: `src/26_historical_band_experts/configs/pilot_basins_60.txt`
- Create: `src/26_historical_band_experts/configs/smoke_basins_6.txt`
- Create: `src/26_historical_band_experts/tests/test_data.py`

**Step 1: Write failing synthetic-data tests**

Test that:

- target indices begin only after 3649 causal history days exist;
- training targets stop on 2006-09-30 and validation targets start on 2006-10-01;
- scalers use training target dates only;
- model input dictionaries contain forcing and statics but no discharge;
- deterministic farthest-point selection returns the same identifiers twice.

**Step 2: Run tests and confirm red**

`pytest src/26_historical_band_experts/tests/test_data.py -v`

**Step 3: Implement data loading**

Use the existing CAMELS-US forcing and discharge loaders. Require `--data-dir`; never hard-code this machine's absolute path. Read discharge only while building the supervised target tensor. Return inputs and targets separately.

Select 60 basins deterministically by standardized Euclidean farthest-point sampling over the 27 allowed static attributes. Start with the basin closest to the static-attribute centroid, then repeatedly add the basin maximizing distance to the selected set. Do not use discharge or discharge-derived attributes.

**Step 4: Freeze lists**

Run:

```powershell
python src/26_historical_band_experts/select_basins.py --count 60 --out src/26_historical_band_experts/configs/pilot_basins_60.txt
```

Create the six-basin smoke list from the first six selections. Record hashes in the experiment configuration.

**Step 5: Run tests and commit**

```powershell
pytest src/26_historical_band_experts/tests/test_data.py -v
git add src/26_historical_band_experts/data.py src/26_historical_band_experts/select_basins.py src/26_historical_band_experts/configs src/26_historical_band_experts/tests/test_data.py
git commit -m "Feat: freeze allowed-data historical-band pilot"
```

### Task 4: Atomic training and validation runner

**Files:**
- Create: `src/26_historical_band_experts/train.py`
- Create: `src/26_historical_band_experts/metrics.py`
- Create: `src/26_historical_band_experts/configs/smoke_v01.json`
- Create: `src/26_historical_band_experts/configs/pilot_v01.json`
- Create: `src/26_historical_band_experts/tests/test_training.py`

**Step 1: Write failing tests**

Test a tiny synthetic run for every model arm:

- two optimizer steps produce finite losses;
- final checkpoint, config snapshot, daily predictions, per-basin metrics, and completion manifest are written under distinct experiment identifiers;
- metric recomputation from saved daily predictions exactly matches the saved table;
- no output path is shared by two arms or seeds.

**Step 2: Run tests and confirm red**

`pytest src/26_historical_band_experts/tests/test_training.py -v`

**Step 3: Implement training**

Use:

- Adam, initial learning rate `1e-3`;
- batch size 256;
- raw-discharge per-basin standard deviation weights `1 / (std + 0.1)^2`;
- gradient norm clipping at 1;
- fixed final epoch, no early stopping;
- deterministic NumPy and PyTorch seeds;
- checkpoint and predictions written atomically via temporary files followed by replacement.

The command must be:

```powershell
python src/26_historical_band_experts/train.py --config <config.json> --variant <variant> --seed <seed> --data-dir <camels_us> --device <cpu|cuda:0>
```

**Step 4: Run tests and commit**

```powershell
pytest src/26_historical_band_experts/tests/test_training.py -v
git add src/26_historical_band_experts/train.py src/26_historical_band_experts/metrics.py src/26_historical_band_experts/configs src/26_historical_band_experts/tests/test_training.py
git commit -m "Feat: add atomic historical-band training runner"
```

### Task 5: Frozen analysis and continuation gate

**Files:**
- Create: `src/26_historical_band_experts/analyze.py`
- Create: `src/26_historical_band_experts/tests/test_analyze.py`
- Create: `src/26_historical_band_experts/registry.csv`

**Step 1: Write failing tests**

Construct synthetic metrics that separately pass and fail each of the six frozen criteria. Test deterministic paired bootstrap output with a fixed analysis seed. Test that a missing run produces `INCOMPLETE`, never `GO`.

**Step 2: Run tests and confirm red**

`pytest src/26_historical_band_experts/tests/test_analyze.py -v`

**Step 3: Implement the analyzer**

Read all nine run manifests, independently reload daily predictions, recompute per-basin Nash–Sutcliffe efficiency, then calculate:

- per-seed median paired difference;
- per-seed basin win fraction;
- number of seeds clearing both thresholds;
- pooled paired-bootstrap 95% confidence interval;
- expert-weight means and maximum mean weight;
- final `GO`, `NO_GO`, or `INCOMPLETE`.

Write `summary.json`, `per_seed.csv`, and `paired_per_basin.csv`. The analyzer must not accept boundary or threshold overrides from the command line.

**Step 4: Run tests and commit**

```powershell
pytest src/26_historical_band_experts/tests/test_analyze.py -v
git add src/26_historical_band_experts/analyze.py src/26_historical_band_experts/tests/test_analyze.py src/26_historical_band_experts/registry.csv
git commit -m "Feat: add frozen historical-band continuation gate"
```

### Task 6: Fresh implementation verification and smoke experiment

**Step 1: Run the isolated implementation suite**

`pytest src/26_historical_band_experts/tests -v`

Expected: zero failures.

**Step 2: Run the six-basin smoke experiment**

Run all three variants for seed 100, two epochs, and the configured batch cap. Use central processing unit if another graphics-processing-unit job is active.

**Step 3: Verify artifacts**

Confirm three completion manifests exist and independently recompute every saved validation metric. Smoke results are wiring evidence only and must not be interpreted as predictive evidence.

**Step 4: Commit only tracked smoke metadata**

Do not commit checkpoints or predictions.

### Task 7: First-round 60-basin experiment

**Step 1: Recheck resource headroom**

Do not terminate or interfere with existing graphics-processing-unit jobs. Start only if memory headroom is sufficient; otherwise keep the experiment pending.

**Step 2: Run nine frozen experiments**

Run three model variants for seeds 100, 200, and 300 with ten epochs. One run writes to one isolated output directory.

**Step 3: Run the frozen analyzer**

`python src/26_historical_band_experts/analyze.py --results-root results/26_historical_band_experts/pilot_v01`

**Step 4: Apply completion-before-verification**

Before any result claim, freshly run:

```powershell
pytest src/26_historical_band_experts/tests -v
python src/26_historical_band_experts/analyze.py --results-root results/26_historical_band_experts/pilot_v01
```

Read the full outputs, verify all nine manifests, and report the actual `GO`, `NO_GO`, or `INCOMPLETE` result. Do not use the formal scoring service in this pilot.

**Step 5: Record result provenance**

Write a tracked result note containing exact commands, commit, configuration hashes, run directories, metrics paths, and the frozen decision. Do not include or commit observed discharge.
