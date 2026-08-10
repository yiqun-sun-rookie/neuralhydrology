# HPC 64-Basin HBV-Lite Reproduction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Execute this plan inline in the current session. No subagent or source-code commit is authorized.

**Goal:** After the complete unified-autoresearch safety test suite passes on Linux, reproduce one predeclared HBV-lite candidate across the frozen 64-basin development set and both development protocols on the high-performance computing cluster.

**Architecture:** One Slurm job creates a fail-if-present attempt root, runs the complete idea-local test suite, and stops before candidate execution on any test failure. If the gate passes, the same immutable source snapshot runs exactly one named candidate against the existing frozen 64-basin development package, followed by an independent evidence check and a complete SHA-256 manifest.

**Tech Stack:** Python 3.11 virtual environment, pytest, NumPy 1.26.4, pandas 2.2.3, PyArrow 17.0.0, Slurm central-processing-unit job, Python audit hooks, SHA-256 manifests.

## Global Constraints

- Use source snapshot `/data1/home/sunyiq/autoresearch64/runs/unified_autoresearch/dlopen_timezone_fix_validation_20260809_seq24`.
- Run the complete `src/unified_autoresearch/tests` suite before the candidate.
- Run exactly one named candidate: `hbv-lite-calibrated-v1`.
- Use exactly the 64 basin identifiers frozen in `development_basins_64_v1.json` and both `forward` and `reverse` development protocols.
- This is a single-candidate reproduction, not a 64-basin or 531-basin formal search.
- Do not read or enumerate the sealed interval from 1989-10-01 through 1999-09-30.
- Do not run `src/fair_benchmark/score.py`.
- Do not use observed discharge as candidate input.
- Do not modify the shared `nh_final` environment, `/data1/home/sunyiq/neuralhydrology`, or any prior output.
- Fail if the exact attempt root already exists.
- Preserve failed artifacts and Slurm logs; do not clean, overwrite, or retry.
- Do not stage or commit the protected source worktree.

---

### Task 1: Freeze the protected boundaries

**Files:**
- Read: `src/unified_autoresearch/evidence/HANDOFF_20260808_HPC_CANDIDATE_BLOCKER.md`
- Read: `docs/hpc/HPC_AGENT_GUIDE.md`
- Create: `docs/superpowers/plans/2026-08-10-hpc-64-basin-hbv-lite-reproduction.md`

**Interfaces:**
- Consumes: source commit `d1e93d46` and mailbox channel `autoresearch-64`.
- Produces: one explicit experiment identifier and one non-overwriting output root.

- [x] **Step 1: Verify the source worktree boundary**

  Require commit `d1e93d46`, no staged files, and only the previously protected modified and untracked files.

- [x] **Step 2: Verify the mailbox boundary**

  Require branch `hpc-mailbox`, channel `autoresearch-64`, and current remote sequence `39` before creating sequence `40`.

### Task 2: Run the Linux safety gate

**Files:**
- Create: `inbox/autoresearch-64/hbv_lite_64_reproduction_seq40.slurm` on the mailbox branch.
- Modify: `inbox/autoresearch-64/cmd.sh` on the mailbox branch.
- Modify: `inbox/autoresearch-64/seq` from `39` to `40` on the mailbox branch.

**Interfaces:**
- Consumes: immutable source snapshot and cluster virtual environment.
- Produces: `evidence/PYTEST_STDOUT.txt`, `evidence/pytest.xml`, and `evidence/TEST_GATE.json` beneath the unique attempt root.

- [x] **Step 1: Refuse a pre-existing output root**

  Exit with code 3 before any test or candidate work if the exact attempt root exists.

- [x] **Step 2: Run the complete idea-local test suite**

  Run `python -m pytest src/unified_autoresearch/tests -q --junitxml=<attempt>/evidence/pytest.xml` with `PYTHONPATH=<snapshot>/src`.

- [x] **Step 3: Enforce the gate**

  Record the process exit code and parsed test totals. If the exit code is nonzero or any test failed or errored, exit without invoking the candidate command.

### Task 3: Run the single 64-basin reproduction

**Files:**
- Read: `/data1/home/sunyiq/autoresearch64/runs/unified_autoresearch/development_packages_real_64_hpc/PACKAGE_MANIFEST.json`
- Create: `<attempt>/candidate_run/`

**Interfaces:**
- Consumes: frozen 64-basin development package with both development protocols.
- Produces: four registered train/predict runtimes and two development score reports for `hbv-lite-calibrated-v1`.

- [ ] **Step 1: Validate the package boundary**

  Require 64 unique frozen basins, protocols `forward` and `reverse`, package manifest self-consistency, and a source declaration limited to `1999-10-01` through `2008-09-30`.

- [ ] **Step 2: Run only the predeclared candidate**

  Invoke `run_single_candidate.py` once with `--candidate hbv_lite`, `--dependencies cluster`, the frozen package root, and the unique candidate output root.

- [ ] **Step 3: Stop after the first attempt**

  On any failure or denied access event, preserve all outputs and logs and do not resubmit.

### Task 4: Independently validate and hash the evidence

**Files:**
- Create: `<attempt>/evidence/REPRODUCTION_SUMMARY.json`
- Create: `<attempt>/evidence/MANIFEST.sha256`

**Interfaces:**
- Consumes: the test gate, candidate summary, four runtime results, and all access logs.
- Produces: one auditable summary and complete relative-path SHA-256 manifest.

- [ ] **Step 1: Require the declared result counts**

  Require `basin_count=64`, `cell_count=64`, `registered_run_count=4`, and `score_report_count=2`.

- [ ] **Step 2: Independently count access denials**

  Parse every `access.jsonl` file and require the total number of events with `decision=deny` to equal zero.

- [ ] **Step 3: Require four successful runtime results**

  Require status `succeeded`, process exit code zero, normalized exit code zero, and complete required outputs for all four runtimes.

- [ ] **Step 4: Hash the complete attempt root**

  Create `evidence/MANIFEST.sha256` using paths relative to the attempt root and verify it with `sha256sum -c`.

### Task 5: Report without changing the source worktree

**Files:**
- Review: protected source worktree status only.

**Interfaces:**
- Consumes: Slurm accounting and immutable evidence.
- Produces: a `GO` or `HOLD` conclusion with exact counts and evidence paths.

- [x] **Step 1: Recheck the source worktree**

  Require commit `d1e93d46`, no staged files, and no source changes introduced by the cluster run.

- [ ] **Step 2: State the scientific boundary**

  A successful reproduction proves Linux cluster execution and reproducibility only; it does not establish superiority over any baseline.

## Verified Outcome

- Slurm job `202306` ran on `icn213` and stopped at the test gate with exit code `10:0` after 1 minute 14 seconds.
- The complete Linux suite collected 278 tests: 209 passed, 8 skipped, 23 failed, and 38 errored.
- The immutable source snapshot omitted two repository-level frozen inputs required by the tests: `src/fair_benchmark/frozen/bundle/track0_statics.csv` and `examples/06-Finetuning/531_basin_list.txt`.
- Seven runtime tests used the workstation-only frozen dependency declaration rather than the separate cluster declaration and were rejected before launch.
- One Linux security test exposed a real audit gap: replacing `os.path.abspath` and `os.path.realpath` allowed a forbidden file read with zero denied events; the later output-contract check returned exit code 2 but did not prove the read was blocked.
- The gate worked as designed: `candidate_run` is absent. No 64-basin candidate, formal search, sealed evaluation read, fair-benchmark scoring, retry, cleanup, source staging, or source commit occurred.

## Authorized Repair Phase

The user authorized the repair and a new isolated attempt after the gate failure. Source commits remain prohibited without separate approval.

### Task 6: Make both frozen dependency environments testable

**Files:**
- Modify: `src/unified_autoresearch/candidates/catalog.py`
- Modify: `src/unified_autoresearch/workflow/recovery.py`
- Modify: `src/unified_autoresearch/workflow/development_loop.py`
- Modify: `src/unified_autoresearch/scripts/run_single_candidate.py`
- Modify: `src/unified_autoresearch/tests/conftest.py`
- Modify: `src/unified_autoresearch/tests/test_development_recovery.py`
- Modify: `src/unified_autoresearch/tests/test_reference_candidates.py`
- Modify: `src/unified_autoresearch/tests/test_frozen_dependency_sets.py`

**Interfaces:**
- Consumes: one of the two existing hardcoded frozen dependency tuples.
- Produces: explicit dependency injection for reference candidates and workflows while preserving the workstation tuple as the default.

- [ ] **Step 1: Add failing portability coverage**

  Require reference candidates, recovery, the full development loop, and the single-candidate command resolver to accept either frozen tuple explicitly; continue rejecting every unregistered tuple.

- [ ] **Step 2: Add a test-only active-frozen-set fixture**

  Select only between the two hardcoded declarations by exact installed-version equality. Fail collection if neither frozen declaration matches; never construct a declaration from arbitrary installed versions.

- [ ] **Step 3: Thread the explicit tuple through the implementations**

  Add optional dependency parameters whose default remains `PINNED_DEPENDENCIES`, validate with `_frozen_dependencies` before creating output, and pass the chosen tuple into every materializer.

### Task 7: Close the Linux path-helper audit bypass

**Files:**
- Modify: `src/unified_autoresearch/runtime/bootstrap.py`
- Test: `src/unified_autoresearch/tests/test_restricted_runtime.py`

**Interfaces:**
- Consumes: the existing failing attack that replaces `os.path.abspath` and `os.path.realpath` before reading a forbidden file.
- Produces: a denied audit event and normalized exit code 2 before the forbidden read can complete.

- [ ] **Step 1: Preserve the Linux red evidence**

  Use Slurm job `202306` and mailbox result 42 as the failing proof: process exit 0, normalized exit 2 only from the output contract, and denied-event count 0.

- [ ] **Step 2: Add immutable lexical containment before canonical containment**

  Reject a path that is lexically outside every allowed root before calling any canonicalizer whose module globals candidate code might replace.

- [ ] **Step 3: Prevent direct replacement of captured path helpers**

  After declared dependency initialization, reject assignment to the path module helpers used by the audit hook and reject replacement of `os.path` itself.

- [ ] **Step 4: Re-run the exact adversarial test**

  Require process exit code 2, normalized exit code 2, at least one denied event, and no predictions output.

### Task 8: Build a complete immutable cluster test snapshot

**Files:**
- Package: `src/unified_autoresearch/`
- Package: `src/fair_benchmark/frozen/bundle/track0_statics.csv`
- Package: `examples/06-Finetuning/531_basin_list.txt`
- Create: a SHA-256-pinned mailbox payload and a new fail-if-present cluster snapshot.

**Interfaces:**
- Consumes: current protected worktree bytes without modifying the worktree.
- Produces: a new snapshot that contains every repository-level file directly referenced by the idea-local tests.

- [ ] **Step 1: Package and hash the exact local bytes**

  Record the payload hash plus the known frozen-file hashes `085e8b5e0e56b42bfe7e6d012ebb6f2f56681059b60c61c04b835b207864a1f2` and `cd2d3d466aca736fcd32042d2b0bde3d0b58e42ba37fe552d97480bd914b9e85`.

- [ ] **Step 2: Extract only into a new cluster directory**

  Refuse an existing snapshot path, extract the payload, and verify all three hashes before tests.

### Task 9: Re-run the gate and the single 64-basin reproduction

**Files:**
- Create: a new Slurm script and a new isolated attempt root.
- Create: `evidence/TEST_GATE.json`, `evidence/REPRODUCTION_SUMMARY.json`, and `evidence/MANIFEST.sha256`.

**Interfaces:**
- Consumes: the repaired immutable snapshot and existing frozen 64-basin development package.
- Produces: either a gate-only HOLD or a complete single-candidate reproduction.

- [ ] **Step 1: Run targeted Linux regression tests**

  Require the path-helper attack and the seven dependency-portability cases to pass before the full suite.

- [ ] **Step 2: Run the complete Linux suite**

  Stop before candidate launch on any failure or error.

- [ ] **Step 3: Run exactly one candidate only if both gates pass**

  Reuse the frozen package, run `hbv-lite-calibrated-v1` once across 64 development basins and both protocols, and preserve every artifact.

- [ ] **Step 4: Independently verify and hash all evidence**

  Require four successful runtimes, zero independently counted denials, complete outputs, and a valid complete manifest.
