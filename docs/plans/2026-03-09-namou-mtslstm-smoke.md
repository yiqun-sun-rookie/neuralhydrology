# Namou MTS-LSTM Smoke Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a minimal Namou/Kuwei MTS-LSTM smoke configuration that proves `mtslstm` can train on Namou data using auto-resampled `1D + 1h` inputs from the existing hourly dataset.

**Architecture:** Reuse the current Namou rain-only setup and switch only the model family and frequency-related settings required by `mtslstm`: `use_frequencies`, per-frequency `seq_length`, and per-frequency `predict_last_n`. Keep the dynamic inputs identical across both branches so failures are attributable to multi-timescale plumbing rather than feature redesign.

**Tech Stack:** YAML configs, `neuralhydrology.nh_run`, `src/namou_kuwei/scripts/validate_config.py`, generic dataset resampling in `neuralhydrology/datasetzoo/basedataset.py`.

---

### Task 1: Freeze the smoke-test scope

**Files:**
- Create: `docs/plans/2026-03-09-namou-mtslstm-smoke.md`
- Reference: `examples/04-Multi-Timescale/1_basin.yml`
- Reference: `test/test_configs/multi_timescale_regression.test.yml`

**Step 1: Keep the objective minimal**

Goal:
- Confirm that Namou data can run through `mtslstm`
- Confirm train, validation, and test evaluation paths work

Non-goals:
- No leadtime comparability yet
- No architecture search
- No autoregression

**Step 2: Freeze the config shape**

Use:
- `dataset: generic`
- `use_frequencies: [1D, 1h]`
- `dynamic_inputs`: same rainfall list for both branches via a single list
- `seq_length`: `1D: 7`, `1h: 168`
- `predict_last_n`: `1D: 1`, `1h: 1`
- `epochs: 1`

### Task 2: Add a smoke config and README note

**Files:**
- Create: `src/namou_kuwei/configs/no_leak/09_mtslstm_smoke/namou_mtslstm_smoke.yml`
- Create: `src/namou_kuwei/configs/no_leak/09_mtslstm_smoke/README.md`

**Step 1: Write the config**

Required keys:
- `model: mtslstm`
- `shared_mtslstm: false`
- `transfer_mtslstm_states: {h: linear, c: linear}`
- `use_frequencies: [1D, 1h]`
- `seq_length: {1D: 7, 1h: 168}`
- `predict_last_n: {1D: 1, 1h: 1}`

**Step 2: Keep the signal simple**

Dynamic inputs:
- `p_aka`
- `p_bandang`
- `p_banpozai`
- `p_banteng`
- `p_kuwei`
- `p_mengwu`
- `p_xiaolishu`
- `p_xinzai`

Static attributes:
- `area`
- `elev_mean`
- `slope_mean`

**Step 3: Document one important caveat**

In the README, note that:
- multi-frequency generic loading resamples with `mean()`
- the `1D` branch therefore sees daily means, not daily accumulations

### Task 3: Validate the config

**Files:**
- Use: `src/namou_kuwei/scripts/validate_config.py`

**Step 1: Run validator**

Run:
```bash
python src/namou_kuwei/scripts/validate_config.py src/namou_kuwei/configs/no_leak/09_mtslstm_smoke/namou_mtslstm_smoke.yml
```

Expected:
- Exit code `0`
- No leakage or schema errors

### Task 4: Run the smoke training

**Files:**
- Use: `src/namou_kuwei/configs/no_leak/09_mtslstm_smoke/namou_mtslstm_smoke.yml`

**Step 1: Start one-epoch training**

Run:
```bash
python -m neuralhydrology.nh_run train --config-file src/namou_kuwei/configs/no_leak/09_mtslstm_smoke/namou_mtslstm_smoke.yml
```

Expected:
- run directory created
- model initialization succeeds
- one epoch completes
- validation runs without frequency-shape errors

### Task 5: Run smoke evaluation

**Files:**
- Use generated run dir from Task 4

**Step 1: Evaluate epoch 1 on test**

Run:
```bash
python -m neuralhydrology.nh_run evaluate --run-dir <run_dir> --period test --epoch 1
```

Expected:
- `test_metrics.csv` exists
- keys include frequency suffixes such as `_1D` and `_1h`

### Task 6: Decide whether to proceed to comparable LT24

**Files:**
- Review run outputs in `results/04_namou_kuwei/`

**Step 1: Gate for the next phase**

Proceed to comparable LT24 only if:
- smoke train passes
- smoke evaluation passes
- no frequency-alignment or resampling errors appear

If that gate passes, the next config should reuse the same `mtslstm` scaffold but switch to the LT24 rain-only feature definition.
