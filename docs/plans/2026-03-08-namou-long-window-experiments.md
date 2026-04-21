# Namou Long-Window Experiments Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add and verify a minimal set of Namou/Kuwei long-window experiment configs to test whether longer single-frequency history improves LT12/LT24 performance before attempting any multi-timescale model.

**Architecture:** Reuse the existing L8 rain-only fair-comparison configs as the controlled baseline and create new configs that change only `experiment_name` and `seq_length`. Keep the model family and data split fixed so the effect of window length remains interpretable. Verify with config validation plus at least one fresh training run.

**Tech Stack:** YAML configs, Python CLI (`neuralhydrology.nh_run`), Namou helper script (`src/namou_kuwei/scripts/run_experiment.py`), pytest where relevant.

---

### Task 1: Document the experiment scope

**Files:**
- Create: `docs/plans/2026-03-08-namou-long-window-experiments.md`
- Reference: `src/namou_kuwei/configs/no_leak/08_model_fair_rain_only/README.md`

**Step 1: Confirm existing evidence**

Read:
- `src/namou_kuwei/configs/no_leak/08_model_fair_rain_only/README.md`
- `results/04_namou_kuwei/L8_window_test_gru_all_leads_seq168_vs336.csv`

Expected:
- Existing evidence says `seq_length=336` helps `LT12/LT24` and hurts `LT1/LT6`.

**Step 2: Freeze the minimal scope**

Scope:
- Models: `gru`, `cudalstm`
- Leadtimes: `LT12h`, `LT24h`
- Windows: `336`, `720`
- Baseline remains existing `168`

**Step 3: Do not widen the matrix**

Explicitly exclude:
- `mtslstm`
- Multi-frequency inputs
- `LT1h`, `LT6h`
- Architecture tuning beyond sequence length

### Task 2: Add long-window GRU configs

**Files:**
- Modify by copying pattern from: `src/namou_kuwei/configs/no_leak/08_model_fair_rain_only/fair_gru_rainonly_pshift12_static_LT12h.yml`
- Modify by copying pattern from: `src/namou_kuwei/configs/no_leak/08_model_fair_rain_only/fair_gru_rainonly_pshift24_static_LT24h.yml`
- Create: `src/namou_kuwei/configs/no_leak/08_model_fair_rain_only/fair_gru_rainonly_pshift12_static_LT12h_seq720.yml`
- Create: `src/namou_kuwei/configs/no_leak/08_model_fair_rain_only/fair_gru_rainonly_pshift24_static_LT24h_seq720.yml`

**Step 1: Write the configs**

Set:
- `experiment_name: L8_WindowTest_GRU_PShift12_Static_LT12h_SL720`
- `experiment_name: L8_WindowTest_GRU_PShift24_Static_LT24h_SL720`
- `seq_length: 720`

Keep everything else identical to the existing GRU LT12/LT24 configs.

**Step 2: Verify syntax**

Run:
```bash
python src/namou_kuwei/scripts/validate_config.py src/namou_kuwei/configs/no_leak/08_model_fair_rain_only/fair_gru_rainonly_pshift12_static_LT12h_seq720.yml
python src/namou_kuwei/scripts/validate_config.py src/namou_kuwei/configs/no_leak/08_model_fair_rain_only/fair_gru_rainonly_pshift24_static_LT24h_seq720.yml
```

Expected:
- Exit code `0`
- No leakage or schema errors

### Task 3: Add long-window CudaLSTM configs

**Files:**
- Modify by copying pattern from: `src/namou_kuwei/configs/no_leak/08_model_fair_rain_only/fair_cudalstm_rainonly_pshift12_static_LT12h.yml`
- Modify by copying pattern from: `src/namou_kuwei/configs/no_leak/08_model_fair_rain_only/fair_cudalstm_rainonly_pshift24_static_LT24h.yml`
- Create: `src/namou_kuwei/configs/no_leak/08_model_fair_rain_only/fair_cudalstm_rainonly_pshift12_static_LT12h_seq336.yml`
- Create: `src/namou_kuwei/configs/no_leak/08_model_fair_rain_only/fair_cudalstm_rainonly_pshift24_static_LT24h_seq336.yml`
- Create: `src/namou_kuwei/configs/no_leak/08_model_fair_rain_only/fair_cudalstm_rainonly_pshift12_static_LT12h_seq720.yml`
- Create: `src/namou_kuwei/configs/no_leak/08_model_fair_rain_only/fair_cudalstm_rainonly_pshift24_static_LT24h_seq720.yml`

**Step 1: Write the configs**

Set:
- `experiment_name: L8_WindowTest_CudaLSTM_PShift12_Static_LT12h_SL336`
- `experiment_name: L8_WindowTest_CudaLSTM_PShift24_Static_LT24h_SL336`
- `experiment_name: L8_WindowTest_CudaLSTM_PShift12_Static_LT12h_SL720`
- `experiment_name: L8_WindowTest_CudaLSTM_PShift24_Static_LT24h_SL720`
- `seq_length: 336` or `720`

Keep `initial_forget_bias: 3` and all other fields unchanged.

**Step 2: Verify syntax**

Run:
```bash
python src/namou_kuwei/scripts/validate_config.py src/namou_kuwei/configs/no_leak/08_model_fair_rain_only/fair_cudalstm_rainonly_pshift12_static_LT12h_seq336.yml
python src/namou_kuwei/scripts/validate_config.py src/namou_kuwei/configs/no_leak/08_model_fair_rain_only/fair_cudalstm_rainonly_pshift24_static_LT24h_seq336.yml
python src/namou_kuwei/scripts/validate_config.py src/namou_kuwei/configs/no_leak/08_model_fair_rain_only/fair_cudalstm_rainonly_pshift12_static_LT12h_seq720.yml
python src/namou_kuwei/scripts/validate_config.py src/namou_kuwei/configs/no_leak/08_model_fair_rain_only/fair_cudalstm_rainonly_pshift24_static_LT24h_seq720.yml
```

Expected:
- Exit code `0`
- No leakage or schema errors

### Task 4: Update experiment notes

**Files:**
- Modify: `src/namou_kuwei/configs/no_leak/08_model_fair_rain_only/README.md`

**Step 1: Add the new config names**

Add a short section for:
- GRU `seq720`
- CudaLSTM `seq336`
- CudaLSTM `seq720`

**Step 2: Keep claims evidence-bound**

Only document:
- What was added
- Which commands to run

Do not claim model quality improvements until fresh runs exist.

### Task 5: Run minimal fresh verification

**Files:**
- Use: `src/namou_kuwei/scripts/run_experiment.py`
- Use: `src/namou_kuwei/configs/no_leak/08_model_fair_rain_only/fair_gru_rainonly_pshift24_static_LT24h_seq720.yml`

**Step 1: Validate the chosen config**

Run:
```bash
python src/namou_kuwei/scripts/validate_config.py src/namou_kuwei/configs/no_leak/08_model_fair_rain_only/fair_gru_rainonly_pshift24_static_LT24h_seq720.yml
```

Expected:
- PASS

**Step 2: Run one fresh training job**

Run:
```bash
python src/namou_kuwei/scripts/run_experiment.py train --config src/namou_kuwei/configs/no_leak/08_model_fair_rain_only/fair_gru_rainonly_pshift24_static_LT24h_seq720.yml --device cpu
```

Expected:
- Training starts successfully
- Run directory created under `results/04_namou_kuwei/`

**Step 3: If runtime is acceptable, queue one CudaLSTM comparator**

Run:
```bash
python src/namou_kuwei/scripts/run_experiment.py train --config src/namou_kuwei/configs/no_leak/08_model_fair_rain_only/fair_cudalstm_rainonly_pshift24_static_LT24h_seq336.yml --device cpu
```

Expected:
- Training starts successfully

### Task 6: Summarize evidence and next steps

**Files:**
- Review: `results/04_namou_kuwei/`
- Optionally modify later: `src/namou_kuwei/configs/no_leak/08_model_fair_rain_only/README.md`

**Step 1: Compare against baseline**

Use:
- Existing `seq168`
- Existing GRU `seq336`
- Fresh GRU `seq720`
- Fresh CudaLSTM `seq336` if available

**Step 2: Make a decision**

Decision rules:
- If `seq720` beats `seq336` on LT24 without obvious instability, extend to LT12.
- If `seq720` is flat or worse, stop the window search and do not introduce `mtslstm`.
- Only revisit `mtslstm` after a separate data design for multi-frequency inputs.
