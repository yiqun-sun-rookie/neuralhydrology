# Namou MTS-LSTM Paper-Aligned Matrix Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a minimal Namou/Kuwei LT24 MTS-LSTM experiment matrix that follows the original paper's sequence-geometry logic instead of the current near-minimal daily context.

**Architecture:** Keep the existing Namou generic dataset and MTS-LSTM training entrypoint, but introduce a new config set whose only intentional variable is the amount of compressed daily history handed to the hourly branch. Preserve the existing rain-only, no-leak LT24 setup while changing the sequence geometry to paper-aligned values and documenting the rationale.

**Tech Stack:** YAML configs, Python pytest, existing Namou config validator, NeuralHydrology multi-timescale config format.

---

### Task 1: Add regression coverage for paper-aligned MTS sequence geometry

**Files:**
- Modify: `test/test_namou_kuwei_validate_config.py`

**Step 1: Write the failing test**

Add a test that asserts the new paper-aligned config directory exists, contains exactly three configs, and that each config:
- uses `use_frequencies: [1D, 1h]`
- uses `predict_last_n.1D = 1` and `predict_last_n.1h = 24`
- uses `seq_length.1h = 336`
- produces the expected compressed daily history count via `seq_length.1D - int(seq_length.1h / 24)`

**Step 2: Run test to verify it fails**

Run: `pytest test/test_namou_kuwei_validate_config.py -k paper_aligned -v`
Expected: FAIL because the new config directory and files do not exist yet.

**Step 3: Write minimal implementation**

Create the new config directory and files referenced by the test.

**Step 4: Run test to verify it passes**

Run: `pytest test/test_namou_kuwei_validate_config.py -k paper_aligned -v`
Expected: PASS

### Task 2: Add the paper-aligned Namou config matrix

**Files:**
- Create: `src/namou_kuwei/configs/no_leak/11_mtslstm_paper_aligned/README.md`
- Create: `src/namou_kuwei/configs/no_leak/11_mtslstm_paper_aligned/mtslstm_prev1d_pshift24_static_LT24h_y24_seq336_d44.yml`
- Create: `src/namou_kuwei/configs/no_leak/11_mtslstm_paper_aligned/mtslstm_prev1d_pshift24_static_LT24h_y24_seq336_d74.yml`
- Create: `src/namou_kuwei/configs/no_leak/11_mtslstm_paper_aligned/mtslstm_prev1d_pshift24_static_LT24h_y24_seq336_d365.yml`

**Step 1: Write the minimal configs**

Use the existing redesigned Namou MTS-LSTM config as the template. Change only:
- experiment names
- `seq_length.1h` to `336`
- `seq_length.1D` to `44`, `74`, and `365`
- any explanatory comments or metadata needed for clarity

Keep:
- `predict_last_n.1D = 1`
- `predict_last_n.1h = 24`
- no-leak date split
- daily `prev1d_sum` branch and hourly `shift24` branch
- `regularization: [tie_frequencies]`

**Step 2: Document the rationale**

In the README, explain:
- the paper benchmark uses `1D=365`, `1h=336`
- the current `1D=15`, `1h=337` setup only compresses one extra day before handoff
- the new matrix isolates compressed-history length while holding the rest of the setup fixed

**Step 3: Validate configs**

Run: `python src/namou_kuwei/scripts/validate_config.py --dir src/namou_kuwei/configs/no_leak/11_mtslstm_paper_aligned`
Expected: all configs pass with no leakage errors

### Task 3: Verify and summarize the new matrix

**Files:**
- Modify: `test/test_namou_kuwei_validate_config.py`
- Create: `src/namou_kuwei/configs/no_leak/11_mtslstm_paper_aligned/README.md`

**Step 1: Run targeted tests**

Run: `pytest test/test_namou_kuwei_validate_config.py -k paper_aligned -v`
Expected: PASS

**Step 2: Run broader Namou tests that touch the daily-branch tooling**

Run: `pytest test/test_namou_kuwei_scripts.py test/test_namou_kuwei_validate_config.py -v`
Expected: PASS

**Step 3: Summarize operator-facing next commands**

List the three training commands to launch the new configs, but do not start training automatically.
