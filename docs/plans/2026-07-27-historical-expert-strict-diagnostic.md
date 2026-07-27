# Historical Expert Strict Diagnostic Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build an auditable seven-combination masking diagnostic and a zero-tolerance recent-only nested reproduction before spending any of the five candidate iterations.

**Architecture:** New version 06 modules import but do not modify version 03–05 code. The masking runner captures the fused representation immediately before the existing version 05 head and applies fixed branch masks in evaluation mode. The nesting runner trains a classic reference and an inert-history nested control in lockstep with identical active parameters and restored random-number states.

**Tech Stack:** Python 3, PyTorch, NumPy, pandas, pytest, existing historical-band data and metric helpers.

---

### Task 1: Freeze experiment identities and provenance

**Files:**
- Modify: `src/26_historical_band_experts/registry.csv`
- Create: `src/26_historical_band_experts/configs/diagnostic_mask_v06.json`
- Create: `src/26_historical_band_experts/configs/strict_nesting_v06.json`
- Test: `src/26_historical_band_experts/tests/test_configs_v06.py`

**Steps:**

1. Write failing tests that require unique experiment families, the frozen 60-basin and target hashes, internal validation dates, new output roots, zero reproduction tolerance, and no version 03–05 output reuse.
2. Run `pytest src/26_historical_band_experts/tests/test_configs_v06.py -q` and confirm failure because the files do not exist.
3. Add the two configuration files and two registry rows.
4. Re-run the test and confirm it passes.
5. Commit with `Phase: freeze strict historical diagnostics`.

### Task 2: Implement branch-mask semantics

**Files:**
- Create: `src/26_historical_band_experts/diagnostics_v06.py`
- Create: `src/26_historical_band_experts/tests/test_diagnostics_v06.py`

**Steps:**

1. Write failing tests for the exact seven nonempty branch combinations.
2. Write a failing test that captures the version 05 fused representation before its head and requires the all-branch result to equal the unmodified forward result exactly.
3. Write failing tests showing that an inactive branch is zeroed after encoding, the output bias is retained once, and model training mode is rejected.
4. Run the new test file and confirm failures are caused by the missing module.
5. Implement only the fused-feature capture and fixed masking helpers.
6. Re-run the new test file and the existing version 05 model tests.
7. Commit with `Feat: add strict historical branch masks`.

### Task 3: Implement the read-only masking runner

**Files:**
- Create: `src/26_historical_band_experts/run_mask_diagnostic_v06.py`
- Modify: `src/26_historical_band_experts/tests/test_diagnostics_v06.py`

**Steps:**

1. Write failing synthetic tests requiring checkpoint identity validation, saved-scaler use, exactly 43,860 pilot predictions, exact all-branch reproduction, finite metrics, atomic output and artifact hashes.
2. Add failing tests for forbidden date ranges, wrong basin or target hashes, nonempty output directories and forbidden input declarations.
3. Run the tests and confirm the expected failures.
4. Implement the smallest runner satisfying the tests without calling the version 05 analyzer.
5. Run the new tests and all historical-band tests.
6. Execute `D06-MASK` against the frozen version 05 checkpoint.
7. Independently recompute its metrics and artifact hashes.
8. Commit with `Phase: record strict branch masking diagnostic`.

### Task 4: Implement the inert-history nested model

**Files:**
- Create: `src/26_historical_band_experts/models_v06.py`
- Create: `src/26_historical_band_experts/tests/test_models_v06.py`

**Steps:**

1. Write a failing test that the nested model has the same 297,217 active parameters as the classic 256-unit model, with identical shapes, order and values.
2. Write a failing test that construction preserves the post-classic central-processor random-number state.
3. Write failing tests that medium and old inputs are neither required nor consumed, and that all inert parameters are frozen.
4. Write a failing train-mode test that saved-and-restored random state gives exact classic and nested predictions and exact post-forward random state.
5. Run the tests and confirm the missing implementation failures.
6. Implement the nested model by deep-copying the classic recent modules and constructing inert history modules inside a forked random-number context.
7. Re-run the new tests on the central processor and, when available, the graphics processor.
8. Commit with `Feat: add strict recent-only nested control`.

### Task 5: Implement one-step and lockstep equality checks

**Files:**
- Create: `src/26_historical_band_experts/train_strict_v06.py`
- Create: `src/26_historical_band_experts/tests/test_training_strict_v06.py`

**Steps:**

1. Write a failing synthetic one-step test comparing batch indices, predictions, losses, gradients, clipped gradients, Adam states and updated parameters with zero tolerance.
2. Write failing tests that deliberately perturb one mask, parameter order and batch index and require immediate failure with the first differing component reported.
3. Run the tests and confirm the missing trainer failures.
4. Implement the minimal paired lockstep step and equality report.
5. Extend the test to two epochs and final evaluation predictions.
6. Run the strict tests and all historical-band tests.
7. Commit with `Feat: add zero-tolerance lockstep trainer`.

### Task 6: Run strict nesting reproduction

**Files:**
- Output only: `results/26_historical_band_experts/strict_nesting_v06/`
- Modify after evidence exists: `src/26_historical_band_experts/registry.csv`
- Create after evidence exists: `docs/technical/historical_expert_strict_diagnostic_v06.md`

**Steps:**

1. Record PyTorch, CUDA, cuDNN, graphics processor, deterministic settings and central-processor and graphics-processor random-number hashes.
2. Run a short graphics-processor lockstep diagnostic and require exact equality.
3. If it passes, run the full 30-epoch seed-100 lockstep reproduction.
4. Require exact equality of final active states and 43,860 validation predictions.
5. Compare the fresh classic result with the frozen version 03 classic artifact; treat any mismatch as a separate historical-environment diagnostic and do not start a candidate.
6. Independently validate manifests, hashes and metrics.
7. Update the registry and technical report with facts, inferences and unknowns separated.
8. Commit with `Phase: record strict nesting reproduction`.

### Task 7: Freeze candidate iteration 1 only after strict reproduction passes

**Files:**
- Create: `src/26_historical_band_experts/models_equal_experts_v06.py`
- Create: `src/26_historical_band_experts/train_equal_experts_v06.py`
- Create: `src/26_historical_band_experts/analyze_equal_experts_v06.py`
- Create: `src/26_historical_band_experts/configs/equal_experts_i01_v06.json`
- Create: `src/26_historical_band_experts/tests/test_equal_experts_v06.py`
- Modify: `src/26_historical_band_experts/registry.csv`

**Steps:**

1. Write failing tests for three identical 32-input, 256-hidden single-layer experts, one flow output, exact frozen lag bands, branch-keyed dropout, 891,649 candidate parameters and 890,436 parameters for the 455-unit capacity control.
2. Write failing tests for isolated output roots, fixed training protocol, stage-one gates and conditional seed policy.
3. Run the tests and confirm expected failures.
4. Implement the minimum candidate, controls, runner and analyzer.
5. Run all historical-band tests and a real graphics-processor smoke run.
6. Freeze the configuration and registry entry before the complete run.
7. Run seed 100 and apply the four frozen gates.
8. Run seeds 200 and 300 only if all four gates pass.
9. Record `E06-I01`; design `E06-I02` only from the resulting evidence.

