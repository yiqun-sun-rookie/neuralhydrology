# Namou TiRex Minimal Validation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a minimal `tirex` model path to the `neuralhydrology` framework and create smoke-ready Namou/Kuwei configs for a first result screen.

**Architecture:** Implement `tirex` as a standard single-frequency model under `neuralhydrology/modelzoo/`, reusing `InputLayer` for feature preparation and the standard head interface for prediction. Keep the first pass small: model registration, focused tests, and minimal Namou configs only.

**Tech Stack:** Python, PyTorch, pytest, YAML configs, `neuralhydrology.modelzoo`, Namou/Kuwei config conventions.

---

### Task 1: Add the failing registration tests

**Files:**
- Modify: `test/test_custom_lstm.py`
- Reference: `test/test_config_runs.py`

**Step 1: Write the failing tests**

Add tests that:
- request `model: tirex` via `get_model()`
- assert the returned model type is `TiRex`
- run a minimal forward pass and assert `y_hat` exists with batch-first output

**Step 2: Run the targeted tests to verify RED**

Run:
```bash
pytest test/test_custom_lstm.py -k tirex -v
```

Expected:
- FAIL because `tirex` is not registered and `TiRex` does not exist

### Task 2: Implement the minimal TiRex adapter

**Files:**
- Create: `neuralhydrology/modelzoo/tirex.py`
- Modify: `neuralhydrology/modelzoo/__init__.py`

**Step 1: Add the model class**

Implement a single-frequency model that:
- subclasses `BaseModel`
- uses `InputLayer`
- projects embeddings to `hidden_size`
- uses a simple temporal backbone compatible with the first-pass dependency situation
- exposes the standard prediction dict with `y_hat`

**Step 2: Register the model**

Update:
- `SINGLE_FREQ_MODELS`
- `get_model()`

so `model: tirex` resolves through the normal factory path.

**Step 3: Run the targeted tests to verify GREEN**

Run:
```bash
pytest test/test_custom_lstm.py -k tirex -v
```

Expected:
- PASS

### Task 3: Add smoke-safe Namou configs

**Files:**
- Create: `src/namou_kuwei/configs/no_leak/12_tirex_smoke/tirex_rainonly_LT1h.yml`
- Create: `src/namou_kuwei/configs/no_leak/12_tirex_smoke/tirex_histflow_LT24h.yml`

**Step 1: Copy the smallest relevant Namou baselines**

Use:
- rain-only `LT1h`
- historical-flow-informed `LT24h`

and swap only the model-specific settings needed for `tirex`.

**Step 2: Keep the first pass minimal**

Use modest sizes so the configs are cheap to validate and inspect:
- modest `hidden_size`
- standard regression head
- existing data splits and target settings

### Task 4: Validate the new configs

**Files:**
- Use: `src/namou_kuwei/scripts/validate_config.py`
- Modify if needed: `test/test_namou_kuwei_validate_config.py`

**Step 1: Add a focused validation test if the validator rejects the new model**

If the validator has model allow/deny logic, write the failing test first and then extend it minimally.

**Step 2: Run config validation**

Run:
```bash
python src/namou_kuwei/scripts/validate_config.py src/namou_kuwei/configs/no_leak/12_tirex_smoke/
```

Expected:
- configs validate without leakage-related errors

### Task 5: Run focused verification

**Files:**
- Verify: `test/test_custom_lstm.py`
- Verify: `test/test_namou_kuwei_validate_config.py`

**Step 1: Run the exact targeted checks**

Run:
```bash
pytest test/test_custom_lstm.py -k tirex -v
pytest test/test_namou_kuwei_validate_config.py -v
```

Expected:
- all targeted tests pass

### Task 6: Prepare the first experiment screen

**Files:**
- Use: `src/namou_kuwei/scripts/run_experiment.py`
- Use: `src/namou_kuwei/configs/no_leak/12_tirex_smoke/`

**Step 1: Document the first four experiments**

The intended first screen is:
- `gru` rain-only `LT1h`
- `tirex` rain-only `LT1h`
- `gru` historical-flow-informed `LT24h`
- `tirex` historical-flow-informed `LT24h`

**Step 2: Stop-or-continue rule**

Continue the TiRex line only if at least one TiRex run shows a credible advantage in:
- rain-only exploitation, or
- long-lead memory handling

Otherwise, stop expanding model work and return to rainfall representation analysis.
