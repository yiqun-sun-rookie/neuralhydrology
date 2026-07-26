# Historical-interval expert protocol repair implementation plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Produce a protocol-compliant v02 rerun of the fixed 60-basin historical-interval
expert pilot without changing the scientific comparison.

**Architecture:** A trusted one-way preparation command creates an allowed target-only bundle.
Candidate training reads only that bundle for supervised targets. Matched multiscale dropout and
strict daily-key analysis repair the two comparison defects. Version 01 remains immutable and
invalid; version 02 uses a new configuration and output root.

**Tech Stack:** Python 3.11, PyTorch, NumPy, pandas, pytest, PowerShell, SHA-256 manifests.

---

### Task 1: Target-only bundle contract

**Files:**
- Create: src/26_historical_band_experts/prepare_targets.py
- Modify: src/26_historical_band_experts/data.py
- Modify: src/26_historical_band_experts/train.py
- Modify: src/26_historical_band_experts/tests/test_data.py
- Modify: src/26_historical_band_experts/tests/test_training.py

**Step 1: Write failing tests**

Add tests that require the real data-loading path to accept a target-only table and expected
hash, reject duplicate or out-of-range dates, reject a hash or basin-list mismatch, and complete
while a patched raw discharge loader raises on every call. Add a command-level test that the
candidate training path has no raw discharge-loader reference.

**Step 2: Verify red**

Run:

    pytest src/26_historical_band_experts/tests/test_data.py src/26_historical_band_experts/tests/test_training.py -v

Expected: new tests fail because the target-bundle interface does not exist.

**Step 3: Implement the minimum contract**

Create a trusted preparation command that writes only basin, date, and observed discharge for
1999-10-01 through 2008-09-30 plus a manifest. Change load_data_pack and train.py to require
--targets-file and --targets-sha256. Validate hash, exact basin set, unique daily keys, finite
values, and date bounds before constructing the target tensor. Remove the raw discharge loader
from candidate loading.

**Step 4: Verify green**

Run the same two test files and confirm all pass.

**Step 5: Commit**

Commit message:

    Fix: isolate supervised targets from sealed observations

### Task 2: Matched dropout placement

**Files:**
- Modify: src/26_historical_band_experts/models.py
- Modify: src/26_historical_band_experts/tests/test_models.py

**Step 1: Write a failing test**

Use a recording dropout module to assert that both multiscale arms apply dropout exactly three
times, once to each hidden state, and never to the concatenated current-forcing or static
features. Assert that the expert gate and heads receive the same dropped states.

**Step 2: Verify red**

Run:

    pytest src/26_historical_band_experts/tests/test_models.py -v

Expected: the fusion arm records one full-feature dropout and the expert gate uses clean states.

**Step 3: Implement the minimum repair**

Drop each encoder state once in both arms, build fusion features from the dropped states, and
use the same dropped states for all expert heads and the gate.

**Step 4: Verify green and commit**

Commit message:

    Fix: match multiscale dropout placement

### Task 3: Strict analyzer integrity

**Files:**
- Modify: src/26_historical_band_experts/analyze.py
- Modify: src/26_historical_band_experts/tests/test_analyze.py

**Step 1: Write failing tests**

Add separate tests for a duplicate basin-date row, a missing day, an extra basin, a changed
observed value in one variant, a non-finite simulation, and an artifact-hash mismatch. Each must
be rejected before metrics are computed.

**Step 2: Verify red**

Run:

    pytest src/26_historical_band_experts/tests/test_analyze.py -v

**Step 3: Implement strict validation**

Require the fixed row count, basin count, date bounds, uniqueness, finiteness, and exact
basin-date-observation equality across variants. Validate all manifest-listed artifact hashes.

**Step 4: Verify green and commit**

Commit message:

    Fix: reject incomplete historical-band evidence

### Task 4: Freeze version 02 inputs

**Files:**
- Create: src/26_historical_band_experts/configs/pilot_v02.json
- Create: src/26_historical_band_experts/configs/smoke_v02.json
- Modify: src/26_historical_band_experts/registry.csv

**Step 1: Generate the trusted bundle**

Run the trusted preparation command once against the frozen 60-basin list. Do not print target
values. Inspect only the manifest and verify that the minimum date is 1999-10-01, maximum date is
2008-09-30, the formal-period emitted-row count is zero, and the basin-list hash matches.

**Step 2: Freeze configuration**

Copy v01 settings exactly except experiment family, result root, target-bundle path, target
bundle hash, and repaired-code identity. Add a distinct v02 registry row with status planned.

**Step 3: Verify and commit**

Run configuration and data-contract tests. Commit message:

    Phase: freeze compliant historical-band pilot

### Task 5: Smoke and nine-run version 02 experiment

**Step 1: Verify resources**

Confirm the existing graphics-processing-unit job is alive and sufficient memory remains. Do
not stop or modify it. Run pilot jobs serially.

**Step 2: Run smoke**

Run all three variants for seed 100 using smoke_v02. Verify manifests, metrics, target-bundle
hash, and zero candidate raw-streamflow reads.

**Step 3: Run nine fixed experiments**

Run all three variants for seeds 100, 200, and 300 with pilot_v02. Never overwrite or reuse v01
or a nonempty v02 run directory.

**Step 4: Analyze and independently recompute**

Run the frozen analyzer, then independently verify every artifact hash, every daily key and
observed value, every basin metric, bootstrap interval, expert weight, and final criterion.

**Step 5: Fresh verification**

Run:

    pytest src/26_historical_band_experts/tests -v
    python src/26_historical_band_experts/analyze.py --results-root results/26_historical_band_experts/pilot_v02
    git diff --check

### Task 6: Independent review and result record

Request an independent code and evidence review. Fix all Critical and Important issues before
any admissible result claim. Write a tracked v02 result note and update only the v02 registry
row. Preserve v01 as protocol_invalid. Commit only after fresh verification.
