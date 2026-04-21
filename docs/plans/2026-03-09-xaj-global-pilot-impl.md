# XAJ Global Pilot Implementation Plan

> Archived note: this implementation plan belongs to the earlier Caravan-oriented `xaj_global_pilot` phase. The active Idea 10 benchmark plan now lives in `docs/plans/2026-03-27-global-conceptual-model-benchmark-impl.md` and follows a `CAMELS-US` first benchmark path.

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build the first-stage XAJ global pilot workflow that creates `basin_registry.csv`, selects the final `pilot_60_basins.csv`, runs `XAJ`, `XAJ + PDD`, and `HBV` on the selected basins, and writes the regime summary table used for the go/no-go decision.

**Architecture:** Create a dedicated `src/xaj_global_pilot/` experiment module that reuses existing loading and model-execution capabilities instead of modifying the dirty `src/hydroagent/` work in place. Basin metadata and regime classification flow into a registry builder, a selector produces the final 60-basin pilot list, and a model catalog plus batch runner execute the three-model matrix and summarize outputs into fixed CSV contracts.

**Tech Stack:** Python, pandas, pathlib, pytest, `src/hydroagent/data_loading.py`, `src/hydroagent/environment.py`, existing `src/hbv_camels_us_531/` runner patterns.

---

### Task 1: Scaffold The Dedicated Pilot Module

**Files:**
- Create: `src/xaj_global_pilot/__init__.py`
- Create: `src/xaj_global_pilot/config.py`
- Create: `test/test_xaj_global_pilot_config.py`

**Step 1: Write the failing test**

```python
from src.xaj_global_pilot.config import (
    PILOT_NAME,
    PILOT_VERSION,
    REGIME_NAMES,
    REGIME_SAMPLE_SIZE,
    SUMMARY_DIRNAME,
)


def test_pilot_constants_are_stable():
    assert PILOT_NAME == "xaj_global_pilot"
    assert PILOT_VERSION == "pilot_v01"
    assert REGIME_SAMPLE_SIZE == 15
    assert REGIME_NAMES == (
        "snow-dominated",
        "humid",
        "semi-humid",
        "semi-arid/arid",
    )
    assert SUMMARY_DIRNAME == "summary"
```

**Step 2: Run test to verify it fails**

Run: `pytest test/test_xaj_global_pilot_config.py -v`
Expected: FAIL with `ModuleNotFoundError` for `src.xaj_global_pilot.config`

**Step 3: Write minimal implementation**

- `config.py` defines:
  - pilot name and version
  - summary/results/logs directory helpers
  - regime labels
  - snow and aridity thresholds
  - minimum required registry columns

**Step 4: Run test to verify it passes**

Run: `pytest test/test_xaj_global_pilot_config.py -v`
Expected: PASS

**Step 5: Commit**

```bash
git add src/xaj_global_pilot/__init__.py src/xaj_global_pilot/config.py test/test_xaj_global_pilot_config.py
git commit -m "Phase: scaffold xaj global pilot module"
```

---

### Task 2: Implement Regime Classification And QC Helpers

**Files:**
- Create: `src/xaj_global_pilot/classification.py`
- Create: `test/test_xaj_global_pilot_classification.py`

**Step 1: Write the failing test**

```python
from src.xaj_global_pilot.classification import classify_regime, qc_record


def test_classify_regime_uses_snow_first():
    record = {
        "snow_fraction": 0.30,
        "temp_coldest_quarter": -3.0,
        "cold_season_precip_fraction": 0.35,
        "aridity_index": 2.2,
    }
    assert classify_regime(record) == "snow-dominated"


def test_classify_regime_uses_aridity_for_non_snow():
    record = {
        "snow_fraction": 0.05,
        "temp_coldest_quarter": 4.0,
        "cold_season_precip_fraction": 0.10,
        "aridity_index": 1.2,
    }
    assert classify_regime(record) == "semi-humid"


def test_qc_record_rejects_high_missing_rate():
    record = {"missing_rate": 0.08, "human_impact_flag": False}
    assert qc_record(record) is False
```

**Step 2: Run test to verify it fails**

Run: `pytest test/test_xaj_global_pilot_classification.py -v`
Expected: FAIL because `classify_regime` and `qc_record` are missing

**Step 3: Write minimal implementation**

- `classify_regime(record)` enforces the snow-first decision tree
- `qc_record(record)` enforces:
  - complete split coverage flag
  - `missing_rate <= 0.05`
  - optional filtering of strongly human-regulated basins

**Step 4: Run test to verify it passes**

Run: `pytest test/test_xaj_global_pilot_classification.py -v`
Expected: PASS

**Step 5: Commit**

```bash
git add src/xaj_global_pilot/classification.py test/test_xaj_global_pilot_classification.py
git commit -m "Phase: add pilot regime classification and qc helpers"
```

---

### Task 3: Build The Basin Registry Generator

**Files:**
- Create: `src/xaj_global_pilot/registry.py`
- Create: `src/xaj_global_pilot/metadata_sources.py`
- Create: `test/test_xaj_global_pilot_registry.py`

**Step 1: Write the failing test**

```python
import pandas as pd

from src.xaj_global_pilot.registry import build_basin_registry


def test_build_basin_registry_adds_required_columns(tmp_path):
    candidates = pd.DataFrame([
        {
            "basin_id": "0001",
            "region": "A",
            "snow_fraction": 0.0,
            "temp_coldest_quarter": 5.0,
            "cold_season_precip_fraction": 0.1,
            "aridity_index": 0.8,
            "missing_rate": 0.0,
            "human_impact_flag": False,
            "split_coverage_ok": True,
        }
    ])

    registry = build_basin_registry(candidates)

    assert "regime" in registry.columns
    assert "data_ok" in registry.columns
    assert "selected_for_pilot" in registry.columns
    assert registry.loc[0, "regime"] == "humid"
    assert registry.loc[0, "data_ok"] is True
```

**Step 2: Run test to verify it fails**

Run: `pytest test/test_xaj_global_pilot_registry.py -v`
Expected: FAIL because `build_basin_registry` is missing

**Step 3: Write minimal implementation**

- `metadata_sources.py` defines narrow loaders for candidate metadata and derived climate fields
- `registry.py`:
  - normalizes candidate rows
  - applies regime classification
  - computes `data_ok`
  - initializes `selected_for_pilot=False`
  - preserves `selection_note`

**Step 4: Run test to verify it passes**

Run: `pytest test/test_xaj_global_pilot_registry.py -v`
Expected: PASS

**Step 5: Commit**

```bash
git add src/xaj_global_pilot/registry.py src/xaj_global_pilot/metadata_sources.py test/test_xaj_global_pilot_registry.py
git commit -m "Phase: add basin registry builder"
```

---

### Task 4: Add Pilot Basin Selection Logic

**Files:**
- Create: `src/xaj_global_pilot/selection.py`
- Create: `test/test_xaj_global_pilot_selection.py`

**Step 1: Write the failing test**

```python
import pandas as pd

from src.xaj_global_pilot.selection import select_pilot_basins


def test_select_pilot_basins_returns_15_per_regime():
    rows = []
    for regime in ("snow-dominated", "humid", "semi-humid", "semi-arid/arid"):
        for idx in range(20):
            rows.append(
                {
                    "basin_id": f"{regime}-{idx}",
                    "regime": regime,
                    "region": f"region-{idx % 6}",
                    "continent": f"continent-{idx % 3}",
                    "area_km2": 100 + idx,
                    "seasonality_index": idx / 20,
                    "data_ok": True,
                    "selected_for_pilot": False,
                    "selection_note": "",
                }
            )
    registry = pd.DataFrame(rows)

    selected = select_pilot_basins(registry)

    assert len(selected) == 60
    assert selected.groupby("regime").size().to_dict() == {
        "snow-dominated": 15,
        "humid": 15,
        "semi-humid": 15,
        "semi-arid/arid": 15,
    }
```

**Step 2: Run test to verify it fails**

Run: `pytest test/test_xaj_global_pilot_selection.py -v`
Expected: FAIL because `select_pilot_basins` is missing

**Step 3: Write minimal implementation**

- filter to `data_ok == True`
- select `15` per regime
- enforce the region cap when feasible
- annotate `selected_for_pilot` and `selection_note`
- keep selection deterministic for reproducibility

**Step 4: Run test to verify it passes**

Run: `pytest test/test_xaj_global_pilot_selection.py -v`
Expected: PASS

**Step 5: Commit**

```bash
git add src/xaj_global_pilot/selection.py test/test_xaj_global_pilot_selection.py
git commit -m "Phase: add pilot basin selection rules"
```

---

### Task 5: Define The Three-Model Catalog

**Files:**
- Create: `src/xaj_global_pilot/model_catalog.py`
- Create: `src/xaj_global_pilot/structures.py`
- Create: `test/test_xaj_global_pilot_model_catalog.py`

**Step 1: Write the failing test**

```python
from src.xaj_global_pilot.model_catalog import get_model_specs


def test_model_catalog_contains_three_locked_models():
    specs = get_model_specs()
    assert tuple(specs.keys()) == ("xaj", "xaj_pdd", "hbv")
    assert specs["xaj"]["uses_snow_module"] is False
    assert specs["xaj_pdd"]["uses_snow_module"] is True
    assert specs["hbv"]["uses_snow_module"] is True
```

**Step 2: Run test to verify it fails**

Run: `pytest test/test_xaj_global_pilot_model_catalog.py -v`
Expected: FAIL because the model catalog is missing

**Step 3: Write minimal implementation**

- `structures.py` defines:
  - fixed `XAJ`-style structure using `UpperZone`
  - fixed `XAJ + PDD`-style structure using `SnowReservoir` plus `UpperZone`
- `model_catalog.py` returns a locked dictionary for:
  - structure builder
  - output subdirectory name
  - whether snow is enabled
  - whether the existing HBV runner path can be reused

**Step 4: Run test to verify it passes**

Run: `pytest test/test_xaj_global_pilot_model_catalog.py -v`
Expected: PASS

**Step 5: Commit**

```bash
git add src/xaj_global_pilot/model_catalog.py src/xaj_global_pilot/structures.py test/test_xaj_global_pilot_model_catalog.py
git commit -m "Phase: lock xaj pilot model catalog"
```

---

### Task 6: Implement The Basin Runner And Metrics Contract

**Files:**
- Create: `src/xaj_global_pilot/runner.py`
- Create: `src/xaj_global_pilot/metrics.py`
- Create: `test/test_xaj_global_pilot_runner.py`

**Step 1: Write the failing test**

```python
import pandas as pd

from src.xaj_global_pilot.runner import run_single_model_basin


class FakeEnv:
    def __init__(self, *args, **kwargs):
        pass

    def run_episode(self, *args, **kwargs):
        return {"best_nse": 0.62}


def test_run_single_model_basin_returns_metrics_row(monkeypatch):
    def fake_load(*args, **kwargs):
        forcing = pd.DataFrame({"prcp": [1.0], "ep": [0.2], "tmean": [3.0]})
        obs = pd.Series([0.5])
        return forcing, obs

    monkeypatch.setattr("src.xaj_global_pilot.runner.load_camels_basin", fake_load)
    monkeypatch.setattr("src.xaj_global_pilot.runner.SuperflexEnv", FakeEnv)

    result = run_single_model_basin("0001", "xaj", "data/camels_us")

    assert result["basin_id"] == "0001"
    assert result["model"] == "xaj"
    assert "nse" in result
    assert "peak_bias" in result
    assert "lowflow_bias" in result
    assert result["run_status"] == "success"
```

**Step 2: Run test to verify it fails**

Run: `pytest test/test_xaj_global_pilot_runner.py -v`
Expected: FAIL because `run_single_model_basin` is missing

**Step 3: Write minimal implementation**

- `runner.py`:
  - reuses `load_camels_basin` from `src/hydroagent/data_loading.py`
  - builds the requested structure from `model_catalog.py`
  - uses `SuperflexEnv` for XAJ and XAJ+PDD execution
  - reuses or wraps the existing `src/hbv_camels_us_531/runner.py` path for `hbv`
- `metrics.py` computes:
  - `nse`
  - `kge`
  - `bias`
  - `peak_bias`
  - `lowflow_bias`

**Step 4: Run test to verify it passes**

Run: `pytest test/test_xaj_global_pilot_runner.py -v`
Expected: PASS

**Step 5: Commit**

```bash
git add src/xaj_global_pilot/runner.py src/xaj_global_pilot/metrics.py test/test_xaj_global_pilot_runner.py
git commit -m "Phase: add xaj pilot basin runner"
```

---

### Task 7: Implement Batch Execution And Summary Tables

**Files:**
- Create: `src/xaj_global_pilot/batch.py`
- Create: `src/xaj_global_pilot/reporting.py`
- Create: `test/test_xaj_global_pilot_batch.py`

**Step 1: Write the failing test**

```python
import pandas as pd

from src.xaj_global_pilot.reporting import summarize_by_regime


def test_summarize_by_regime_emits_required_columns():
    rows = pd.DataFrame([
        {
            "basin_id": "b1",
            "regime": "humid",
            "model": "xaj",
            "period": "test",
            "nse": 0.5,
            "kge": 0.4,
            "bias": 0.1,
            "peak_bias": 0.2,
            "lowflow_bias": -0.1,
            "run_status": "success",
            "error_message": "",
        }
    ])

    summary = summarize_by_regime(rows)

    assert "median_nse" in summary.columns
    assert "n_failed" in summary.columns
    assert "delta_nse_vs_xaj" in summary.columns
```

**Step 2: Run test to verify it fails**

Run: `pytest test/test_xaj_global_pilot_batch.py -v`
Expected: FAIL because the reporting functions are missing

**Step 3: Write minimal implementation**

- `batch.py`:
  - reads `pilot_60_basins.csv`
  - runs all three models per basin
  - keeps going after failures
  - writes one metrics CSV per `model x basin`
- `reporting.py`:
  - assembles `all_basins_metrics.csv`
  - groups by `model x regime`
  - writes `by_regime_metrics.csv`

**Step 4: Run test to verify it passes**

Run: `pytest test/test_xaj_global_pilot_batch.py -v`
Expected: PASS

**Step 5: Commit**

```bash
git add src/xaj_global_pilot/batch.py src/xaj_global_pilot/reporting.py test/test_xaj_global_pilot_batch.py
git commit -m "Phase: add xaj pilot batch reporting"
```

---

### Task 8: Add Command-Line Entry Points

**Files:**
- Create: `src/xaj_global_pilot/scripts/__init__.py`
- Create: `src/xaj_global_pilot/scripts/run_xaj_global_pilot.py`
- Create: `test/test_xaj_global_pilot_cli.py`

**Step 1: Write the failing test**

```python
from src.xaj_global_pilot.scripts.run_xaj_global_pilot import build_parser


def test_cli_exposes_registry_select_run_subcommands():
    parser = build_parser()
    subparsers = parser._subparsers._group_actions[0]
    names = set(subparsers.choices.keys())
    assert {"build-registry", "select-basins", "run-pilot"} <= names
```

**Step 2: Run test to verify it fails**

Run: `pytest test/test_xaj_global_pilot_cli.py -v`
Expected: FAIL because the CLI module is missing

**Step 3: Write minimal implementation**

- `run_xaj_global_pilot.py` defines subcommands:
  - `build-registry`
  - `select-basins`
  - `run-pilot`
  - optionally `summarize`
- each subcommand delegates into the experiment module without modifying `src/hydroagent/scripts/run_batch.py`

**Step 4: Run test to verify it passes**

Run: `pytest test/test_xaj_global_pilot_cli.py -v`
Expected: PASS

**Step 5: Commit**

```bash
git add src/xaj_global_pilot/scripts/__init__.py src/xaj_global_pilot/scripts/run_xaj_global_pilot.py test/test_xaj_global_pilot_cli.py
git commit -m "Phase: add xaj pilot cli"
```

---

### Task 9: Record Usage And Provenance

**Files:**
- Create: `src/xaj_global_pilot/README.md`
- Modify: `docs/plans/2026-03-09-xaj-global-pilot-design.md`

**Step 1: Write the failing test**

There is no meaningful automated failing test for prose-only documentation. Skip a failing test and instead require a manual verification step.

**Step 2: Write minimal implementation**

- `README.md` documents:
  - expected metadata inputs
  - output file contracts
  - CLI usage
  - relationship to `src/hydroagent/` and `src/hbv_camels_us_531/`
- update the design doc only if implementation decisions materially narrow the original plan

**Step 3: Run verification**

Run: `Get-Content src/xaj_global_pilot/README.md`
Expected: README describes the registry, selection, run, and summary stages

**Step 4: Commit**

```bash
git add src/xaj_global_pilot/README.md docs/plans/2026-03-09-xaj-global-pilot-design.md
git commit -m "Docs: record xaj pilot usage and provenance"
```

---

### Task 10: End-To-End Verification

**Files:**
- Test: `test/test_xaj_global_pilot_config.py`
- Test: `test/test_xaj_global_pilot_classification.py`
- Test: `test/test_xaj_global_pilot_registry.py`
- Test: `test/test_xaj_global_pilot_selection.py`
- Test: `test/test_xaj_global_pilot_model_catalog.py`
- Test: `test/test_xaj_global_pilot_runner.py`
- Test: `test/test_xaj_global_pilot_batch.py`
- Test: `test/test_xaj_global_pilot_cli.py`

**Step 1: Run focused unit tests**

Run: `pytest test/test_xaj_global_pilot_config.py test/test_xaj_global_pilot_classification.py test/test_xaj_global_pilot_registry.py test/test_xaj_global_pilot_selection.py test/test_xaj_global_pilot_model_catalog.py test/test_xaj_global_pilot_runner.py test/test_xaj_global_pilot_batch.py test/test_xaj_global_pilot_cli.py -v`
Expected: PASS

**Step 2: Run a smoke registry build**

Run: `python src/xaj_global_pilot/scripts/run_xaj_global_pilot.py build-registry`
Expected: `results/xaj_global_pilot/pilot_v01/summary/basin_registry.csv` is created

**Step 3: Run a smoke selection**

Run: `python src/xaj_global_pilot/scripts/run_xaj_global_pilot.py select-basins`
Expected: `results/xaj_global_pilot/pilot_v01/summary/pilot_60_basins.csv` is created

**Step 4: Run a one-basin smoke pilot**

Run: `python src/xaj_global_pilot/scripts/run_xaj_global_pilot.py run-pilot --basin-id <known_basin_id>`
Expected: three per-model basin result files plus updated summary CSVs

**Step 5: Commit**

```bash
git add src/xaj_global_pilot test
git commit -m "Phase: complete xaj global pilot workflow"
```
