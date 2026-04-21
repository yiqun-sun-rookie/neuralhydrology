# Namou MTS-LSTM Daily-Branch Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Redesign the Namou LT24 `mtslstm` experiment so the `1D` branch consumes explicit non-leaking previous-day rainfall features instead of hourly rainfall columns auto-resampled with `mean()`.

**Architecture:** Keep the core `generic` dataset and `mtslstm` model unchanged. Add a Namou-specific data-derivation script that builds a sibling dataset containing extra hourly columns whose values represent previous-day rainfall totals repeated across the following day. Then point a new LT24 config at that derived dataset and use per-frequency `dynamic_inputs` so the `1D` branch sees only the new daily-designed columns while the `1h` branch keeps the existing shifted hourly rainfall inputs.

**Tech Stack:** Python script under `src/namou_kuwei/scripts/`, pytest, xarray/pandas, YAML configs, `src/namou_kuwei/scripts/validate_config.py`, `neuralhydrology.nh_run`.

---

### Task 1: Freeze the daily-branch feature definition

**Files:**
- Create: `docs/plans/2026-03-09-namou-mtslstm-daily-branch-redesign.md`
- Reference: `neuralhydrology/datasetzoo/basedataset.py`
- Reference: `examples/04-Multi-Timescale/1_basin.yml`

**Step 1: Preserve the framework boundary**

Do not modify:
- `neuralhydrology/datasetzoo/basedataset.py`
- `neuralhydrology/modelzoo/mtslstm.py`

Reason:
- The current issue is feature design, not multi-frequency plumbing.

**Step 2: Define the new 1D inputs**

For each hourly rainfall column `p_*`, derive:
- previous-day total rainfall
- repeated for every hour of the next day

Naming:
- `p_aka_prev1d_sum`
- `p_bandang_prev1d_sum`
- ...

**Step 3: Keep leakage constraints explicit**

The first day will be `NaN` after the one-day shift. That is acceptable because training already uses warmup and sample validation.

### Task 2: Add a tested data-derivation script

**Files:**
- Create: `src/namou_kuwei/scripts/build_mtslstm_daily_branch_data.py`
- Modify: `test/test_namou_kuwei_scripts.py`

**Step 1: Write failing tests first**

Add tests for:
- derived previous-day totals are correct on a toy hourly series
- repeated hourly values stay constant within the day
- the script preserves required original columns and writes the expected output layout

**Step 2: Implement the minimal script**

The script should:
- read a source Namou generic dataset directory
- copy basin lists and attributes
- load each netCDF basin file
- append `*_prev1d_sum` columns
- write a sibling generic dataset directory with the augmented netCDF files
- optionally refresh a simple manifest

### Task 3: Materialize the derived Namou dataset

**Files:**
- Create generated directory: `data/namou_kuwei/hourly_mtslstm_prev1d`

**Step 1: Run the builder**

Run:
```bash
python src/namou_kuwei/scripts/build_mtslstm_daily_branch_data.py --source data/namou_kuwei/hourly --output data/namou_kuwei/hourly_mtslstm_prev1d
```

Expected:
- netCDF exists under `time_series/`
- attributes and basin files are copied
- new rainfall columns are present

### Task 4: Add a redesigned LT24 config

**Files:**
- Modify: `src/namou_kuwei/configs/no_leak/10_mtslstm_fair_rain_only/README.md`
- Create: `src/namou_kuwei/configs/no_leak/10_mtslstm_fair_rain_only/redesigned_mtslstm_prev1d_pshift24_static_LT24h_y24.yml`

**Step 1: Point to the derived dataset**

Set:
- `data_dir: data/namou_kuwei/hourly_mtslstm_prev1d`

**Step 2: Split dynamic inputs by frequency**

Set:
- `dynamic_inputs.1D` to the new `*_prev1d_sum` columns
- `dynamic_inputs.1h` to the existing `p_*_shift24` columns

Keep:
- `use_frequencies: [1D, 1h]`
- `predict_last_n.1h = 24`
- `regularization: [tie_frequencies]`

### Task 5: Validate and run the redesigned experiment

**Files:**
- Use: `src/namou_kuwei/scripts/validate_config.py`
- Use: `src/namou_kuwei/scripts/run_experiment.py`

**Step 1: Validate config**

Run:
```bash
python src/namou_kuwei/scripts/validate_config.py src/namou_kuwei/configs/no_leak/10_mtslstm_fair_rain_only/redesigned_mtslstm_prev1d_pshift24_static_LT24h_y24.yml
```

Expected:
- exit code `0`

**Step 2: Run training**

Run:
```bash
python src/namou_kuwei/scripts/run_experiment.py train --config src/namou_kuwei/configs/no_leak/10_mtslstm_fair_rain_only/redesigned_mtslstm_prev1d_pshift24_static_LT24h_y24.yml --device cpu
```

Expected:
- run completes
- test evaluation can be produced for at least the final checkpoint

### Task 6: Compare against the prior evidence

**Files:**
- Review: `results/04_namou_kuwei/`

**Step 1: Compare only the LT24 line**

Compare:
- first comparable `mtslstm`
- standard `mtslstm` with `predict_last_n.1h = 24`
- redesigned previous-day-input `mtslstm`
- GRU `seq336`

**Step 2: Stop or continue based on evidence**

Decision:
- If redesigned `mtslstm` remains clearly below GRU `seq336`, stop the MTS-LSTM line.
- If redesigned `mtslstm` materially improves over prior MTS-LSTM runs, only then consider small tuning.
