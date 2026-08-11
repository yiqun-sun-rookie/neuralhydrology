# Unseen 64-Basin Confirmation Implementation Plan

> **For agentic workers:** Execute this plan inline in the current session. Do not delegate because this task has one tightly coupled evidence chain.

**Goal:** Obtain an honest post-selection confirmation for the already selected HBV-lite rainfall-runoff model on 64 development-only basins whose outcomes were not available during candidate selection.

**Architecture:** Freeze ranks 65 through 128 from the existing static-attribute-only farthest-point ordering, which are disjoint from the previously used ranks 1 through 64. Commit the selection and confirmation registry before any new discharge data are opened, then run exactly one candidate with seed 29 on the high-performance computing cluster and audit the result without using the sealed final period or the fair-benchmark scoring service.

**Tech Stack:** Python 3.11, JSON, pandas, NumPy, PyArrow, pytest, Slurm, SHA-256 manifests.

## Global Constraints

- Do not read, enumerate, or score 1989-10-01 through 1999-09-30.
- Do not run `src/fair_benchmark/score.py`.
- Run one declared candidate only; do not search candidates, seeds, hyperparameters, or checkpoints.
- Candidate prediction inputs remain Maurer forcing plus the 27 approved static attributes.
- The new basin selection may read only the frozen static-attribute table and eligible-basin list.
- Use ranks 65 through 128 of the existing deterministic ordering; overlap with the historical 64-basin set must equal zero.
- Keep seed 29, both development protocols, dependency versions, candidate source, and resource limits unchanged.
- Use new output roots and never delete, overwrite, or repair failed evidence in place.
- A result is prospective only if the selection registry is committed before the Slurm job starts.
- Do not claim baseline superiority.

---

### Task 1: Freeze the disjoint static-only basin block

**Files:**
- Modify: `src/unified_autoresearch/selection/basins.py`
- Create: `src/unified_autoresearch/selection/development_basins_confirmation_64_v1.json`
- Create: `src/unified_autoresearch/tests/test_prospective_confirmation_selection.py`

**Interfaces:**
- Consumes: `select_development_basins(static_path, basin_path, count=128)`.
- Produces: `select_development_basin_block(..., rank_start=65, count=64) -> list[str]` and `freeze_selection_block(...) -> dict`.

- [ ] **Step 1: Write a failing test for the exact block.**

```python
ranked = select_development_basins(FROZEN_STATIC_TABLE, ELIGIBLE_BASIN_LIST, count=128)
selected = select_development_basin_block(
    FROZEN_STATIC_TABLE, ELIGIBLE_BASIN_LIST, rank_start=65, count=64
)
assert selected == ranked[64:128]
assert len(selected) == len(set(selected)) == 64
assert set(selected).isdisjoint(FROZEN_HISTORICAL_64)
```

- [ ] **Step 2: Run the focused test and require an import failure.**

Run: `python -m pytest src/unified_autoresearch/tests/test_prospective_confirmation_selection.py -q`

- [ ] **Step 3: Implement strict rank and count validation.**

Reject booleans, ranks below 1, counts below 1, and ranges beyond the 531 eligible basins. Derive the block by computing the full prefix ending at `rank_start + count - 1` and slicing it; do not add a second selection algorithm.

- [ ] **Step 4: Freeze the exact record exclusively.**

The record must include schema version 1, method `deterministic_standardized_farthest_point_block_v1`, static and eligible-list hashes, rank range `[65, 128]`, historical-selection SHA-256, and the exact 64 basin identifiers.

- [ ] **Step 5: Run the focused tests and require all tests to pass.**

---

### Task 2: Allow only the newly frozen record through development builders

**Files:**
- Modify: `src/unified_autoresearch/data/packages.py`
- Modify: `src/unified_autoresearch/tests/test_prospective_confirmation_selection.py`

**Interfaces:**
- Consumes: the exact new selection JSON.
- Produces: `load_frozen_selection()` acceptance for exactly three records: 8 historical basins, 64 historical basins, and 64 unseen confirmation basins.

- [ ] **Step 1: Add a failing acceptance and drift-rejection test.**

```python
assert load_frozen_selection(CONFIRMATION_PATH)["selection_rank_range"] == [65, 128]
drifted["basins"] = list(reversed(drifted["basins"]))
with pytest.raises(ValueError, match="frozen development basin selection mismatch"):
    load_frozen_selection(drifted_path)
```

- [ ] **Step 2: Add the exact hard-coded confirmation record to `FROZEN_DEVELOPMENT_SELECTIONS`.**

Do not load an arbitrary JSON record dynamically; the builder must continue rejecting reproducible but unapproved selections.

- [ ] **Step 3: Verify the historical 8- and 64-basin selection tests remain unchanged and pass.**

Run: `python -m pytest src/unified_autoresearch/tests/test_basin_selection.py src/unified_autoresearch/tests/test_scaleup_64_selection.py src/unified_autoresearch/tests/test_scaleup_64_data_base.py src/unified_autoresearch/tests/test_prospective_confirmation_selection.py -q`

---

### Task 3: Commit the prospective registry before opening new discharge data

**Files:**
- Create: `src/unified_autoresearch/evidence/PROSPECTIVE_CONFIRMATION_REGISTRY_20260811.json`
- Modify: `src/unified_autoresearch/tests/test_prospective_confirmation_selection.py`

**Interfaces:**
- Consumes: automatic recommendation evidence SHA-256 `7bb8d23ea03b0cffc0390c4fb6993fd2f6449cc65a47d1674771971a241a723e`, historical scale manifest SHA-256 `2702f7c59890872cecea4947ca60ef266935eaadf8097b4ebed9022e26a2ed13`, and the new selection hash.
- Produces: a committed, result-independent registry for one candidate, seed 29, 64 unseen basins, and two development protocols.

- [ ] **Step 1: Write a test that recomputes the selection and verifies zero overlap without reading discharge.**
- [ ] **Step 2: Record the fixed and changed factors.**

The only changed factor is the basin set. Fixed factors are candidate identifier, candidate category, seed, dependencies, two protocols, date bounds 1999-10-01 through 2008-09-30, source hashes, and access policy.

- [ ] **Step 3: Run all unified-auto-research tests.**

Run: `python -m pytest src/unified_autoresearch/tests -q`

- [ ] **Step 4: Run `git diff --check`, verify the changed-file boundary, commit with a `Feat:` prefix, and push the source branch.**

---

### Task 4: Run one unseen-basin confirmation on the high-performance computing cluster

**Files:**
- Create through the mailbox: an isolated Slurm script and immutable evidence root.
- Do not modify candidate-method source during this task.

**Interfaces:**
- Consumes: the committed source revision and registry from Task 3.
- Produces: one source root, one package root, one candidate run, one evidence summary, and one complete SHA-256 manifest.

- [ ] **Step 1: Create a source snapshot from the exact committed revision and verify its hash.**
- [ ] **Step 2: Build the development-only source and package on a compute node.**

Assert all dates are within 1999-10-01 through 2008-09-30, sealed dates present equal zero, basin count equals 64, and overlap with the historical selection equals zero.

- [ ] **Step 3: Run the complete local safety test gate inside the snapshot.**
- [ ] **Step 4: Run only `hbv-lite-calibrated-v1`, seed 29, through forward and reverse protocols.**
- [ ] **Step 5: Require four registered processes with process and normalized exit codes zero, complete required outputs, and zero independently counted denied events.**
- [ ] **Step 6: Seal the summary and all artifacts in a new manifest; never overwrite the output root.**

---

### Task 5: Close the promotion audit without overstating the claim

**Files:**
- Modify: `src/unified_autoresearch/evidence/AUTOMATIC_REHEARSAL_PROMOTION_AUDIT_20260811.json`
- Modify: `src/unified_autoresearch/tests/test_promotion_gate.py`

**Interfaces:**
- Consumes: the new selection, job accounting, summary hash, manifest hash, runtime-source hashes, and access logs.
- Produces: technical scale-up, unseen-holdout independence, and overall promotion decisions.

- [ ] **Step 1: Independently verify the manifest and recompute metrics from development-only candidate cells.**
- [ ] **Step 2: Compare candidate identity and all nine runtime-source hashes with the automatic recommendation.**
- [ ] **Step 3: Record the historical result as retrospective technical evidence and the disjoint result as prospective unseen-holdout evidence.**
- [ ] **Step 4: Run focused and complete tests, then commit and push the final audit.**
- [ ] **Step 5: Report technical and prospective decisions separately; do not claim superiority over a baseline.**
