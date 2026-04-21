# Global Conceptual Model Benchmark Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Extend the current `src/xaj_global_pilot/` workflow into a publishable conceptual benchmark pipeline that first runs a fair 15-basin screening experiment with three primary snow-capable models, `XAJ+PDD`, `HBV`, and `GR4J+PDD`, while using bare `XAJ` and `GR4J` as ablations only, then scales the three-model benchmark to CAMELS-US 531 basins only if the screening signal is strong enough.

**Architecture:** Reuse the existing `src/xaj_global_pilot/` module instead of starting a new idea module. Lock the benchmark protocol in config and manifest files, keep a distinction between the three primary benchmark models and two ablation-only models, route all model runs through a single fair runner contract, and generate fixed summary tables for both the 15-basin screening phase and the optional 531-basin scale-up phase. Do not modify dirty `src/hydroagent/` internals unless the benchmark is blocked.

**Tech Stack:** Python, pandas, pathlib, pytest, `src/xaj_global_pilot/`, `src/hydroagent/data_loading.py`, `src/hydroagent/environment.py`, `src/hbv_camels_us_531/`, CSV manifests, lightweight PowerShell launch scripts.

---

### Task 1: Freeze The Benchmark Protocol And Basin Manifests

**Files:**
- Modify: `src/xaj_global_pilot/config.py`
- Create: `src/xaj_global_pilot/configs/conceptual_benchmark_15_basins.csv`
- Create: `src/xaj_global_pilot/configs/conceptual_benchmark_camels_us_531.txt`
- Modify: `test/test_xaj_global_pilot_config.py`

**Step 1: Write the failing test**

Add assertions to `test/test_xaj_global_pilot_config.py` for:

- `BENCHMARK_NAME == "global_conceptual_model_benchmark"`
- `SCREENING_VERSION == "screening_v01"`
- `FULL_VERSION == "camels_us_531_v01"`
- `DEFAULT_CALIBRATION_TRIALS == 5000`
- `DEFAULT_RESTARTS == 3`
- `WARMUP_DAYS == 365`
- train/test windows match the benchmark note:
  - train: `1990-10-01` to `1995-09-30`
  - test: `2000-10-01` to `2005-09-30`

**Step 2: Run test to verify it fails**

Run: `pytest test/test_xaj_global_pilot_config.py -v`
Expected: FAIL because the new benchmark constants and manifest helpers do not exist yet.

**Step 3: Write minimal implementation**

- Add benchmark constants and helper path functions to `src/xaj_global_pilot/config.py`.
- Keep the old pilot constants only if still needed by existing code; otherwise migrate callers to the new names.
- Create `src/xaj_global_pilot/configs/conceptual_benchmark_15_basins.csv` with columns:
  - `basin_id`
  - `regime`
  - `region`
  - `selection_note`
- Create `src/xaj_global_pilot/configs/conceptual_benchmark_camels_us_531.txt` by reusing the canonical 531 basin list already used elsewhere in the repo.

**Step 4: Run test to verify it passes**

Run: `pytest test/test_xaj_global_pilot_config.py -v`
Expected: PASS

**Step 5: Commit**

```bash
git add src/xaj_global_pilot/config.py src/xaj_global_pilot/configs test/test_xaj_global_pilot_config.py
git commit -m "Phase: lock conceptual benchmark protocol"
```

---

### Task 2: Split The Model Catalog Into Primary Benchmark Models And Ablations

**Files:**
- Modify: `src/xaj_global_pilot/structures.py`
- Modify: `src/xaj_global_pilot/model_catalog.py`
- Modify: `test/test_xaj_global_pilot_model_catalog.py`

**Step 1: Write the failing test**

Update `test/test_xaj_global_pilot_model_catalog.py` to assert:

- `tuple(specs["primary"].keys()) == ("xaj_pdd", "hbv", "gr4j_pdd")`
- `tuple(specs["ablations"].keys()) == ("xaj", "gr4j")`
- each spec exposes:
  - `uses_snow_module`
  - `parameter_count`
  - `solver_name`
  - `family`
  - `structure_builder`
- every primary model has `uses_snow_module is True`
- every ablation model has `uses_snow_module is False`

**Step 2: Run test to verify it fails**

Run: `pytest test/test_xaj_global_pilot_model_catalog.py -v`
Expected: FAIL because the catalog does not yet distinguish the three-model primary benchmark from the ablation-only models.

**Step 3: Write minimal implementation**

- Add `build_gr4j_structure()` and `build_gr4j_pdd_structure()` to `src/xaj_global_pilot/structures.py`.
- Reuse SuperflexPy-compatible elements already vendored in the repo.
- Extend `get_model_specs()` so it returns separate `primary` and `ablations` sections.
- Record the metadata that later feeds paper tables:
  - `parameter_count`
  - `solver_name`
  - `family`
  - `uses_snow_module`

**Step 4: Run test to verify it passes**

Run: `pytest test/test_xaj_global_pilot_model_catalog.py -v`
Expected: PASS

**Step 5: Commit**

```bash
git add src/xaj_global_pilot/structures.py src/xaj_global_pilot/model_catalog.py test/test_xaj_global_pilot_model_catalog.py
git commit -m "Phase: add gr4j benchmark variants"
```

---

### Task 3: Unify The Fair Runner Contract Across Primary Models And Ablations

**Files:**
- Modify: `src/xaj_global_pilot/runner.py`
- Modify: `src/xaj_global_pilot/metrics.py`
- Modify: `test/test_xaj_global_pilot_runner.py`
- Modify: `test/test_xaj_global_pilot_metrics.py`

**Step 1: Write the failing test**

Add runner coverage for:

- `gr4j` basin run succeeds through the SuperflexPy path
- `gr4j_pdd` uses temperature input when available
- the runner can be called in `primary` mode and in `ablation` mode
- every run result includes:
  - `basin_id`
  - `model`
  - `period`
  - `nse`
  - `kge`
  - `bias`
  - `peak_bias`
  - `lowflow_bias`
  - `run_status`
  - `error_message`
  - `parameter_count`
  - `solver_name`
  - `family`
- train/test periods and warmup are read from config instead of hard-coded ad hoc values

**Step 2: Run test to verify it fails**

Run: `pytest test/test_xaj_global_pilot_runner.py test/test_xaj_global_pilot_metrics.py -v`
Expected: FAIL because the runner does not yet support the benchmark-vs-ablation distinction or the GR4J variants with the new metadata fields.

**Step 3: Write minimal implementation**

- Keep one public entrypoint: `run_single_model_basin(...)`.
- Route `xaj` and `xaj_pdd` through the existing NumPy calibration path.
- Route `hbv`, `gr4j`, and `gr4j_pdd` through the SuperflexPy path.
- Apply the same benchmark split, warmup, trial budget, and restart count for all models.
- Preserve failure visibility by returning a structured failed row instead of raising.
- Add a simple flag or model-group selector so downstream scripts can request:
  - primary benchmark runs only
  - ablations only
  - both, but never by accident
- If validation is not used in this paper, do not invent it; keep the runner aligned with the benchmark note.

**Step 4: Run test to verify it passes**

Run: `pytest test/test_xaj_global_pilot_runner.py test/test_xaj_global_pilot_metrics.py -v`
Expected: PASS

**Step 5: Commit**

```bash
git add src/xaj_global_pilot/runner.py src/xaj_global_pilot/metrics.py test/test_xaj_global_pilot_runner.py test/test_xaj_global_pilot_metrics.py
git commit -m "Phase: unify five-model benchmark runner"
```

---

### Task 4: Add A Dedicated 15-Basin Screening Batch And Go/No-Go Summaries

**Files:**
- Modify: `src/xaj_global_pilot/batch.py`
- Modify: `src/xaj_global_pilot/reporting.py`
- Create: `src/xaj_global_pilot/scripts/run_conceptual_screening.py`
- Modify: `test/test_xaj_global_pilot_batch.py`
- Modify: `test/test_xaj_global_pilot_reporting.py`
- Create: `test/test_xaj_global_pilot_screening_cli.py`

**Step 1: Write the failing test**

Add tests that expect screening outputs:

- one row per `model x basin` in `all_basins_metrics.csv`
- `by_regime_metrics.csv` with median NSE/KGE and success counts
- `win_counts.csv` with basin-level best-model counts
- `ablation_deltas.csv` showing the snow-module gain for:
  - `xaj_pdd` vs `xaj`
  - `gr4j_pdd` vs `gr4j`
- CLI parser accepting:
  - `--manifest`
  - `--primary-only`
  - `--include-ablations`
  - `--trials`
  - `--restarts`
  - `--output-version`

**Step 2: Run test to verify it fails**

Run: `pytest test/test_xaj_global_pilot_batch.py test/test_xaj_global_pilot_reporting.py test/test_xaj_global_pilot_screening_cli.py -v`
Expected: FAIL because the dedicated screening script and summary tables do not exist yet.

**Step 3: Write minimal implementation**

- Reuse the existing batch/reporting module rather than copying logic into scripts.
- Make the screening batch read `src/xaj_global_pilot/configs/conceptual_benchmark_15_basins.csv`.
- By default, run the three primary models plus the two ablations in screening mode.
- Write outputs under:
  - `results/10_global_conceptual_model_benchmark/screening_v01/all_basins_metrics.csv`
  - `results/10_global_conceptual_model_benchmark/screening_v01/by_regime_metrics.csv`
  - `results/10_global_conceptual_model_benchmark/screening_v01/win_counts.csv`
  - `results/10_global_conceptual_model_benchmark/screening_v01/ablation_deltas.csv`
  - `results/10_global_conceptual_model_benchmark/screening_v01/go_no_go_summary.md`
- In `go_no_go_summary.md`, force a one-line verdict:
  - `Go`
  - `Conditional Go`
  - `No-Go`
- Make the markdown summary clearly separate:
  - primary benchmark conclusion
  - ablation conclusion about PDD contribution

**Step 4: Run test to verify it passes**

Run: `pytest test/test_xaj_global_pilot_batch.py test/test_xaj_global_pilot_reporting.py test/test_xaj_global_pilot_screening_cli.py -v`
Expected: PASS

**Step 5: Commit**

```bash
git add src/xaj_global_pilot/batch.py src/xaj_global_pilot/reporting.py src/xaj_global_pilot/scripts/run_conceptual_screening.py test/test_xaj_global_pilot_batch.py test/test_xaj_global_pilot_reporting.py test/test_xaj_global_pilot_screening_cli.py
git commit -m "Phase: add 15-basin conceptual screening workflow"
```

---

### Task 5: Verify The 15-Basin Screening On Real Data

**Files:**
- Modify: `src/xaj_global_pilot/scripts/run_conceptual_screening.py`
- Create: `test/test_xaj_global_pilot_screening_smoke.py`

**Step 1: Write the failing test**

Create a smoke test that:

- monkeypatches the runner
- executes the screening CLI on a tiny manifest
- verifies the expected CSV and markdown outputs are created

**Step 2: Run test to verify it fails**

Run: `pytest test/test_xaj_global_pilot_screening_smoke.py -v`
Expected: FAIL because the smoke helper contract is incomplete.

**Step 3: Run the real screening workflow**

Run:

```bash
python -m src.xaj_global_pilot.scripts.run_conceptual_screening --manifest src/xaj_global_pilot/configs/conceptual_benchmark_15_basins.csv --trials 5000 --restarts 3
```

Expected:

- the screening output directory is created
- the three primary models are always attempted
- the two ablation models are attempted only when screening defaults request them or when `--include-ablations` is set
- failures remain visible in the output CSV
- `go_no_go_summary.md` contains a verdict and short evidence bullets

**Step 4: Run test to verify it passes**

Run: `pytest test/test_xaj_global_pilot_screening_smoke.py -v`
Expected: PASS

**Step 5: Commit**

```bash
git add src/xaj_global_pilot/scripts/run_conceptual_screening.py test/test_xaj_global_pilot_screening_smoke.py results/10_global_conceptual_model_benchmark/screening_v01
git commit -m "Phase: run conceptual screening benchmark"
```

---

### Task 6: Add The Conditional CAMELS-US 531 Scale-Up Path For The Three Primary Models

**Files:**
- Create: `src/xaj_global_pilot/hpc/run_conceptual_benchmark_chunk.py`
- Create: `src/xaj_global_pilot/hpc/build_conceptual_benchmark_chunks.py`
- Create: `src/xaj_global_pilot/hpc/conceptual_benchmark_camels_us_531.ps1`
- Create: `test/test_xaj_global_pilot_hpc_chunking.py`

**Step 1: Write the failing test**

Add a chunking test that expects:

- 531 basin IDs are partitioned into stable chunk files
- chunk order is deterministic
- the chunk runner receives `model`, `chunk-file`, `trials`, and `restarts`

**Step 2: Run test to verify it fails**

Run: `pytest test/test_xaj_global_pilot_hpc_chunking.py -v`
Expected: FAIL because the HPC chunking scripts do not exist yet.

**Step 3: Write minimal implementation**

- Put all scale-up logic under `src/xaj_global_pilot/hpc/`.
- Build chunk manifests from `src/xaj_global_pilot/configs/conceptual_benchmark_camels_us_531.txt`.
- Keep the 531 path disabled by default until the screening verdict is `Go` or `Conditional Go`.
- Default the 531 run matrix to the three primary models only:
  - `xaj_pdd`
  - `hbv`
  - `gr4j_pdd`
- Do not schedule bare `xaj` or bare `gr4j` for 531 basins unless a later paper-specific need appears.
- Write outputs under:
  - `results/10_global_conceptual_model_benchmark/camels_us_531_v01/<model>/`
  - `results/10_global_conceptual_model_benchmark/camels_us_531_v01/summary/`

**Step 4: Run test to verify it passes**

Run: `pytest test/test_xaj_global_pilot_hpc_chunking.py -v`
Expected: PASS

**Step 5: Commit**

```bash
git add src/xaj_global_pilot/hpc test/test_xaj_global_pilot_hpc_chunking.py
git commit -m "Phase: add 531-basin conceptual benchmark chunking"
```

---

### Task 7: Add Paper-Ready Aggregate Tables And Figures

**Files:**
- Create: `src/xaj_global_pilot/scripts/summarize_conceptual_benchmark.py`
- Modify: `src/xaj_global_pilot/reporting.py`
- Create: `test/test_xaj_global_pilot_paper_summary.py`

**Step 1: Write the failing test**

Add a summary test that expects:

- `table_overall_metrics.csv`
- `table_parameter_efficiency.csv`
- `figure_manifest.json`

and verifies that parameter-efficiency is computed as metric divided by parameter count without mutating the raw benchmark tables.

**Step 2: Run test to verify it fails**

Run: `pytest test/test_xaj_global_pilot_paper_summary.py -v`
Expected: FAIL because the paper-summary script does not exist yet.

**Step 3: Write minimal implementation**

- Generate fixed paper-facing assets from the raw CSVs instead of mixing analysis logic into the runner.
- At minimum support:
  - overall median NSE/KGE by model
  - by-regime medians
  - parameter-efficiency ranking
  - basin-level best-model map manifest
- Keep primary benchmark tables separate from ablation tables so the main paper never accidentally mixes unfair no-snow models into the headline result.
- Keep the figure generation contract simple; the plotting backend can be added later.

**Step 4: Run test to verify it passes**

Run: `pytest test/test_xaj_global_pilot_paper_summary.py -v`
Expected: PASS

**Step 5: Commit**

```bash
git add src/xaj_global_pilot/scripts/summarize_conceptual_benchmark.py src/xaj_global_pilot/reporting.py test/test_xaj_global_pilot_paper_summary.py
git commit -m "Phase: add paper summary exports for conceptual benchmark"
```

---

### Task 8: Run The End-To-End Verification Suite Before Claiming Progress

**Files:**
- Test: `test/test_xaj_global_pilot_config.py`
- Test: `test/test_xaj_global_pilot_model_catalog.py`
- Test: `test/test_xaj_global_pilot_runner.py`
- Test: `test/test_xaj_global_pilot_metrics.py`
- Test: `test/test_xaj_global_pilot_batch.py`
- Test: `test/test_xaj_global_pilot_reporting.py`
- Test: `test/test_xaj_global_pilot_screening_cli.py`
- Test: `test/test_xaj_global_pilot_screening_smoke.py`
- Test: `test/test_xaj_global_pilot_hpc_chunking.py`
- Test: `test/test_xaj_global_pilot_paper_summary.py`

**Step 1: Run the targeted unit and integration tests**

Run:

```bash
pytest test/test_xaj_global_pilot_config.py test/test_xaj_global_pilot_model_catalog.py test/test_xaj_global_pilot_runner.py test/test_xaj_global_pilot_metrics.py test/test_xaj_global_pilot_batch.py test/test_xaj_global_pilot_reporting.py test/test_xaj_global_pilot_screening_cli.py test/test_xaj_global_pilot_screening_smoke.py test/test_xaj_global_pilot_hpc_chunking.py test/test_xaj_global_pilot_paper_summary.py -v
```

Expected: PASS

**Step 2: Re-run the real screening workflow if outputs were invalidated**

Run:

```bash
python -m src.xaj_global_pilot.scripts.run_conceptual_screening --manifest src/xaj_global_pilot/configs/conceptual_benchmark_15_basins.csv --trials 5000 --restarts 3
```

Expected: the screening summary files are regenerated without manual patching.

**Step 3: If screening verdict is `Go` or `Conditional Go`, dry-run the 531 chunk builder**

Run:

```bash
python -m src.xaj_global_pilot.hpc.build_conceptual_benchmark_chunks
```

Expected: deterministic chunk files are created for the 531-basin list.

**Step 4: Commit**

```bash
git add src/xaj_global_pilot test docs/plans
git commit -m "Phase: verify conceptual benchmark pipeline"
```

---

## Decision Gates

### Gate A: After Task 5

Continue only if the 15-basin screening yields one of:

- `Go`: clear regime-dependent pattern and interpretable XAJ role
- `Conditional Go`: promising signal but one fairness issue still needs cleanup

Stop or pause if:

- `No-Go`: GR4J swamps the story, or results are too mixed to justify 531 basins

### Gate B: After Task 8

Choose paper framing based on the actual evidence:

- `WRR-upgrade candidate`: strong regime-dependent structure story
- `JH/HESS baseline`: benchmark-gap story plus fair large-sample comparison

For the paper:

- main benchmark tables should use only `XAJ+PDD`, `HBV`, and `GR4J+PDD`
- bare `XAJ` and bare `GR4J` belong in ablation figures or supplement only

Do not use `global` in the title or abstract if the completed evidence is CAMELS-US only.
