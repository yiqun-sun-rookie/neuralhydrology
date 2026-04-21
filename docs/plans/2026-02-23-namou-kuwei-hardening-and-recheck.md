# Namou Kuwei Hardening And Recheck Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Harden Kuwei experiment scripts, then re-evaluate usability and data-leakage status with fresh evidence.

**Architecture:** Keep changes minimal and local to `src/namou_kuwei/scripts/`. First lock behavior with tests for command construction and metric-file discovery, then implement the smallest code changes to pass tests. Finally run end-to-end verification commands (config validation, compare, smoke train/evaluate).

**Tech Stack:** Python, pytest, subprocess-based CLI orchestration, YAML configs.

---

### Task 1: Add Tests For Script Hardening Targets

**Files:**
- Create: `test/test_namou_kuwei_scripts.py`
- Test: `src/namou_kuwei/scripts/run_experiment.py`

**Step 1: Write failing tests**

Add tests for:
- `_find_metrics_file` selects highest epoch metrics file.
- `run_train(..., device="cpu")` passes `--gpu -1` to `nh_run`.
- `run_train(..., device="cuda:0")` passes `--gpu 0` to `nh_run`.

**Step 2: Run tests to verify they fail**

Run:
```bash
pytest test/test_namou_kuwei_scripts.py -q
```
Expected:
- At least one test fails because current implementation does not map `device` to `--gpu`.

**Step 3: Commit checkpoint**

```bash
git add test/test_namou_kuwei_scripts.py
git commit -m "test: add namou kuwei script hardening tests"
```

---

### Task 2: Implement Minimal Script Fixes

**Files:**
- Modify: `src/namou_kuwei/scripts/run_experiment.py`
- Test: `test/test_namou_kuwei_scripts.py`

**Step 1: Add minimal device-to-gpu mapping helper**

Implement helper converting:
- `cpu` -> `-1`
- `cuda` / `cuda:0` -> `0`
- `cuda:<n>` -> `<n>`
- numeric strings -> same numeric

**Step 2: Apply helper in training paths**

Use mapped `--gpu` argument in:
- `run_train(...)`
- `run_quick(...)`

Do not alter model logic or config semantics.

**Step 3: Run focused tests**

Run:
```bash
pytest test/test_namou_kuwei_scripts.py -q
```
Expected:
- All tests pass.

**Step 4: Commit checkpoint**

```bash
git add src/namou_kuwei/scripts/run_experiment.py test/test_namou_kuwei_scripts.py
git commit -m "fix: map namou kuwei script device option to nh_run gpu flag"
```

---

### Task 3: Re-evaluate Usability And Leakage Status

**Files:**
- Modify: none (verification only)

**Step 1: Re-check no-leak configs**

Run:
```bash
python src/namou_kuwei/scripts/validate_config.py src/namou_kuwei/configs/no_leak
```
Expected:
- All no_leak configs valid.
- Existing warning for `seq2seq_ar_24h.yml` is documented.

**Step 2: Re-check full config landscape for risk visibility**

Run:
```bash
python src/namou_kuwei/scripts/validate_config.py src/namou_kuwei/configs
```
Expected:
- `archive_legacy` failures are reported (known historical leakage/overlap issues).

**Step 3: Re-check result usability**

Run:
```bash
python src/namou_kuwei/scripts/run_experiment.py compare --results-dir results/04_namou_kuwei --metric NSE
```
Expected:
- Comparison table prints successfully.
- Best runs align with documented L3/L5/L6 conclusions.

**Step 4: Smoke train/evaluate to confirm runnable path**

Run:
```bash
python src/namou_kuwei/scripts/run_experiment.py train --config src/namou_kuwei/configs/generated/repro_smoke_L3_AR_LT1h_ep1.yml --device cpu
```
Then evaluate latest run (or via direct `nh_run evaluate`).

Expected:
- Training command executes with mapped GPU flag (`--gpu -1`).
- Evaluation artifacts and metrics are generated.

---

### Task 4: Final Verification Summary

**Files:**
- Modify: none (reporting only)

**Step 1: Collect evidence**

Capture outputs from:
- pytest focused tests
- no_leak validation
- full-config validation
- compare command
- smoke train/evaluate

**Step 2: Report status**

Provide:
- whether Kuwei scripts are usable now
- whether active `no_leak` configs are leakage-safe
- what leakage risks remain in historical configs
- any residual risks for future work
