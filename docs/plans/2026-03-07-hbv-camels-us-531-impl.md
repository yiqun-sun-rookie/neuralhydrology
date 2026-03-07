# CAMELS-US 531 Fixed-Structure HBV Baseline Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a fixed-structure HBV-style CAMELS-US 531-basin benchmark runner aligned with the existing LSTM temporal split and basin list.

**Architecture:** A new `src/hbv_camels_us_531/` module will define one fixed HBV-style structure and orchestrate per-basin train/validation/test evaluation by reusing `src/hydroagent/data_loading.py` and `src/hydroagent/environment.py`. Batch execution writes one basin-level CSV and one aggregate summary, while keeping HydroAgent's agent loop untouched.

**Tech Stack:** Python, pandas, numpy, optuna, vendored SuperflexPy (`1.3.2-15-g75d93c3` actual code state), pytest.

---

### Task 1: Scaffold A Dedicated HBV Baseline Module

**Files:**
- Create: `src/hbv_camels_us_531/__init__.py`
- Create: `src/hbv_camels_us_531/config.py`
- Create: `src/hbv_camels_us_531/structure.py`
- Test: `test/test_hbv_camels_us_531_structure.py`

**Step 1: Write the failing test**

```python
from hbv_camels_us_531.config import (
    TRAIN_START_DATE,
    TRAIN_END_DATE,
    VALIDATION_START_DATE,
    VALIDATION_END_DATE,
    TEST_START_DATE,
    TEST_END_DATE,
)
from hbv_camels_us_531.structure import build_fixed_hbv_structure


def test_dates_match_531_benchmark():
    assert TRAIN_START_DATE == "1990-10-01"
    assert TRAIN_END_DATE == "1995-09-30"
    assert VALIDATION_START_DATE == "1995-10-01"
    assert VALIDATION_END_DATE == "2000-09-30"
    assert TEST_START_DATE == "2000-10-01"
    assert TEST_END_DATE == "2005-09-30"


def test_fixed_structure_has_expected_components():
    structure = build_fixed_hbv_structure()
    layer_types = [layer["type"] for layer in structure["layers"]]
    assert layer_types == [
        "SnowReservoir",
        "UnsaturatedReservoir",
        "PowerReservoir",
        "LinearReservoir",
    ]
    assert structure["lags"][0]["type"] == "HalfTriangularLag"
```

**Step 2: Run test to verify it fails**

Run: `pytest test/test_hbv_camels_us_531_structure.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'hbv_camels_us_531'`

**Step 3: Write minimal implementation**

- `config.py` defines the canonical dates and canonical basin-list path
- `structure.py` defines one fixed structure builder returning a stable JSON-like dict
- `__init__.py` exports the public helpers

**Step 4: Run test to verify it passes**

Run: `pytest test/test_hbv_camels_us_531_structure.py -v`
Expected: PASS

**Step 5: Commit**

```bash
git add src/hbv_camels_us_531 test/test_hbv_camels_us_531_structure.py
git commit -m "Feat: scaffold HBV CAMELS-US 531 baseline module"
```

---

### Task 2: Add A Single-Basin Data And Evaluation Contract

**Files:**
- Create: `src/hbv_camels_us_531/runner.py`
- Test: `test/test_hbv_camels_us_531_runner.py`

**Step 1: Write the failing test**

```python
from hbv_camels_us_531.runner import split_periods


def test_split_periods_returns_three_named_windows():
    periods = split_periods()
    assert periods["train"] == ("1990-10-01", "1995-09-30")
    assert periods["validation"] == ("1995-10-01", "2000-09-30")
    assert periods["test"] == ("2000-10-01", "2005-09-30")
```

**Step 2: Run test to verify it fails**

Run: `pytest test/test_hbv_camels_us_531_runner.py -v`
Expected: FAIL because `split_periods` does not exist

**Step 3: Write minimal implementation**

- `split_periods()` returns the three benchmark windows
- define a `BasinRunResult` dataclass with:
  - `basin_id`
  - `train_nse`
  - `validation_nse`
  - `test_nse`
  - `status`
  - `error`
  - `best_params`

**Step 4: Run test to verify it passes**

Run: `pytest test/test_hbv_camels_us_531_runner.py -v`
Expected: PASS

**Step 5: Commit**

```bash
git add src/hbv_camels_us_531/runner.py test/test_hbv_camels_us_531_runner.py
git commit -m "Feat: define HBV basin runner contracts"
```

---

### Task 3: Implement Fixed-Structure Single-Basin Execution

**Files:**
- Modify: `src/hbv_camels_us_531/runner.py`
- Test: `test/test_hbv_camels_us_531_runner.py`

**Step 1: Write the failing test**

Add a pure unit test using monkeypatch:

```python
from hbv_camels_us_531.runner import run_single_basin


def test_run_single_basin_returns_result_with_metrics(monkeypatch):
    def fake_loader(*args, **kwargs):
        import pandas as pd
        idx = pd.date_range("1990-10-01", periods=10, freq="D")
        forcing = pd.DataFrame({"prcp": 1.0, "ep": 0.2, "tmean": 5.0}, index=idx)
        obs = pd.Series(1.0, index=idx)
        return forcing, obs, 100.0

    class FakeEnv:
        def parse_structure(self, structure_json):
            self.structure_json = structure_json

        def auto_calibrate(self, forcing_data, obs_data):
            return {"nse": 0.7, "optimized_params": {"soil_Smax": 100.0}, "qsim": obs_data.copy()}

        def run_simulation(self, forcing_data, params=None):
            import pandas as pd
            return pd.Series(1.0, index=forcing_data.index)

    monkeypatch.setattr("hbv_camels_us_531.runner.load_camels_basin", fake_loader)
    monkeypatch.setattr("hbv_camels_us_531.runner.SuperflexEnv", FakeEnv)

    result = run_single_basin("01022500")
    assert result.status == "ok"
    assert result.train_nse == 0.7
```

**Step 2: Run test to verify it fails**

Run: `pytest test/test_hbv_camels_us_531_runner.py -v`
Expected: FAIL because `run_single_basin` is incomplete

**Step 3: Write minimal implementation**

- load train data with `load_camels_basin`
- build the fixed structure
- instantiate `SuperflexEnv`
- calibrate on train
- run validation and test with locked train parameters via `run_simulation`
- compute NSE for each period
- return a `BasinRunResult`

**Step 4: Run tests**

Run: `pytest test/test_hbv_camels_us_531_runner.py -v`
Expected: PASS

**Step 5: Commit**

```bash
git add src/hbv_camels_us_531/runner.py test/test_hbv_camels_us_531_runner.py
git commit -m "Feat: run fixed HBV baseline for one basin"
```

---

### Task 4: Implement Batch Execution And CSV Summary

**Files:**
- Create: `src/hbv_camels_us_531/batch.py`
- Create: `src/hbv_camels_us_531/reporting.py`
- Test: `test/test_hbv_camels_us_531_batch.py`

**Step 1: Write the failing test**

```python
from pathlib import Path

from hbv_camels_us_531.batch import summarize_results
from hbv_camels_us_531.runner import BasinRunResult


def test_summarize_results_computes_basic_statistics(tmp_path: Path):
    results = [
        BasinRunResult("a", 0.7, 0.6, 0.5, "ok", "", {}),
        BasinRunResult("b", 0.8, 0.7, 0.7, "ok", "", {}),
        BasinRunResult("c", None, None, None, "failed", "boom", {}),
    ]
    summary = summarize_results(results)
    assert summary["n_basins"] == 3
    assert summary["n_success"] == 2
    assert summary["mean_test_nse"] == 0.6
    assert summary["n_test_ge_06"] == 1
```

**Step 2: Run test to verify it fails**

Run: `pytest test/test_hbv_camels_us_531_batch.py -v`
Expected: FAIL because batch helpers do not exist

**Step 3: Write minimal implementation**

- `summarize_results(results)` computes aggregate metrics from successful basins only
- add CSV writing helpers for basin rows and aggregate summary
- keep failure rows in basin-level CSV

**Step 4: Run tests**

Run: `pytest test/test_hbv_camels_us_531_batch.py -v`
Expected: PASS

**Step 5: Commit**

```bash
git add src/hbv_camels_us_531/batch.py src/hbv_camels_us_531/reporting.py test/test_hbv_camels_us_531_batch.py
git commit -m "Feat: add HBV batch summary and reporting"
```

---

### Task 5: Add CLI Entry Point

**Files:**
- Create: `src/hbv_camels_us_531/scripts/run_hbv_camels_us_531.py`
- Test: `test/test_hbv_camels_us_531_cli.py`

**Step 1: Write the failing test**

```python
from hbv_camels_us_531.scripts.run_hbv_camels_us_531 import build_parser


def test_cli_accepts_single_and_batch_modes():
    parser = build_parser()
    args = parser.parse_args(["--basin-id", "01022500"])
    assert args.basin_id == "01022500"
    args = parser.parse_args(["--basin-file", "src/full_531_basins/data/531_basin_list.txt"])
    assert args.basin_file.endswith("531_basin_list.txt")
```

**Step 2: Run test to verify it fails**

Run: `pytest test/test_hbv_camels_us_531_cli.py -v`
Expected: FAIL because CLI module does not exist

**Step 3: Write minimal implementation**

- parser supports:
  - `--basin-id`
  - `--basin-file`
  - `--output-dir`
  - `--data-root`
- single-basin mode runs `run_single_basin`
- batch mode iterates over basin-file IDs and writes CSV outputs

**Step 4: Run tests**

Run: `pytest test/test_hbv_camels_us_531_cli.py -v`
Expected: PASS

**Step 5: Commit**

```bash
git add src/hbv_camels_us_531/scripts/run_hbv_camels_us_531.py test/test_hbv_camels_us_531_cli.py
git commit -m "Feat: add HBV CAMELS-US baseline CLI"
```

---

### Task 6: Add A Real-Data Smoke Test

**Files:**
- Create: `test/test_hbv_camels_us_531_real_data.py`

**Step 1: Write the failing test**

```python
import pytest

from hbv_camels_us_531.runner import run_single_basin


def test_real_camels_basin_smoke():
    try:
        result = run_single_basin("01022500")
    except FileNotFoundError:
        pytest.skip("CAMELS-US data not available locally")

    assert result.status in {"ok", "failed"}
```

**Step 2: Run test to verify behavior**

Run: `pytest test/test_hbv_camels_us_531_real_data.py -v`
Expected: either SKIP if data missing or PASS with a concrete result object

**Step 3: Tighten as needed**

- if runtime is too long, document this as a smoke/integration test rather than default-fast unit coverage

**Step 4: Commit**

```bash
git add test/test_hbv_camels_us_531_real_data.py
git commit -m "Chore: add HBV real-data smoke test"
```

---

### Task 7: Record Dependency Provenance

**Files:**
- Modify: `docs/plans/2026-03-07-hbv-camels-us-531-design.md`
- Create: `src/hbv_camels_us_531/README.md`

**Step 1: Write the failing doc check**

Manual check: README must explicitly state:

- benchmark alignment source
- fixed structure definition
- actual SuperflexPy commit `75d93c3`
- note that vendored code state is `1.3.2-15-g75d93c3`, not exact tag `1.3.2`

**Step 2: Write implementation**

- add README with run commands and dependency provenance

**Step 3: Verify**

Run: `Get-Content src/hbv_camels_us_531/README.md`
Expected: includes the four provenance points above

**Step 4: Commit**

```bash
git add src/hbv_camels_us_531/README.md docs/plans/2026-03-07-hbv-camels-us-531-design.md
git commit -m "Docs: record HBV baseline dependency provenance"
```

---

### Task 8: Full Verification

**Files:**
- Verify only

**Step 1: Run unit tests**

Run: `pytest test/test_hbv_camels_us_531_structure.py test/test_hbv_camels_us_531_runner.py test/test_hbv_camels_us_531_batch.py test/test_hbv_camels_us_531_cli.py -v`
Expected: PASS

**Step 2: Run smoke test**

Run: `pytest test/test_hbv_camels_us_531_real_data.py -v`
Expected: PASS or SKIP with clear data-missing reason

**Step 3: Run one manual basin**

Run:

```bash
python src/hbv_camels_us_531/scripts/run_hbv_camels_us_531.py --basin-id 01022500
```

Expected:

- prints train/validation/test NSE
- writes outputs under the chosen output directory

**Step 4: Run a mini batch**

Run:

```bash
python src/hbv_camels_us_531/scripts/run_hbv_camels_us_531.py --basin-file src/full_531_basins/configs/camels_us/data_splits/1_basin.txt
```

Expected:

- creates basin-level CSV
- creates aggregate summary CSV

**Step 5: Commit**

```bash
git add src/hbv_camels_us_531 test
git commit -m "Feat: complete HBV CAMELS-US 531 baseline runner"
```
