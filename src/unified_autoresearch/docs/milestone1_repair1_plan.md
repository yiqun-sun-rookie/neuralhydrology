# Milestone One Repair Evidence Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build one non-overwritable milestone-one repair evidence root, bind it to a complete SHA-256 fingerprint, and create a read-only clean audit snapshot before two independent reviews.

**Architecture:** A small evidence builder runs the existing test suite before creating the final run root, then exercises the real registry and scheduler lock. It stores raw Git bytes and test outputs under one artifact directory root, appends the resulting fingerprint to the registry with external receipts, verifies the final chain, and copies the exact fingerprint manifests plus final evidence into a read-only snapshot.

**Tech Stack:** Python, SQLite, Git, pytest, psutil, SHA-256.

---

### Task 1: Specify the non-overwritable evidence package

**Files:**
- Create: `src/unified_autoresearch/tests/test_evidence_package.py`
- Create: `src/unified_autoresearch/evidence_package.py`

1. Write tests proving a failed test command creates no final run root.
2. Run the focused tests and confirm failure because the builder does not exist.
3. Implement the minimum builder that runs the supplied test command and exclusively creates the requested root.
4. Run the focused tests and the complete unified automatic research test suite.

### Task 2: Seal registry, artifacts, and raw version-control evidence

**Files:**
- Modify: `src/unified_autoresearch/tests/test_evidence_package.py`
- Modify: `src/unified_autoresearch/evidence_package.py`

1. Write tests requiring the configured real scheduler lock, one external receipt per record, raw NUL-delimited Git status bytes, raw binary Git diff bytes, and recursive coverage of the artifact directory root.
2. Confirm the new tests fail for the required missing behavior.
3. Implement the registry sequence and fingerprint construction without reading final evaluation data.
4. Verify the fingerprint internally and recompute every saved manifest entry.

### Task 3: Create and validate the clean read-only snapshot

**Files:**
- Modify: `src/unified_autoresearch/tests/test_evidence_package.py`
- Modify: `src/unified_autoresearch/evidence_package.py`

1. Write tests requiring a root-hash-derived snapshot name, exact copied-file hashes, read-only files, and refusal to replace an existing snapshot.
2. Confirm the tests fail, implement the smallest snapshot builder, and rerun all tests.
3. Generate `runs/unified_autoresearch/milestone1_repair1/` once and validate it from disk.
4. Run the full suite from the snapshot without writing into the snapshot.

### Task 4: Independent audit gate

**Files:**
- Create after review: `src/unified_autoresearch/evidence/audits/milestone1_repair1_audit.md`
- Create after review: `src/unified_autoresearch/evidence/audits/milestone1_repair1_targeted_verification.md`
- Modify after review: `src/unified_autoresearch/evidence/PROGRESS.md`

1. Dispatch two fresh tasks with no implementation conversation history: one complete audit and one targeted adversarial verification.
2. Require both tasks to use only the read-only snapshot and temporary output directories.
3. If either task finds a defect, reproduce it with a failing test before modifying executable behavior.
4. Record restricted candidate-environment admission only if both final verdicts are PASS.
