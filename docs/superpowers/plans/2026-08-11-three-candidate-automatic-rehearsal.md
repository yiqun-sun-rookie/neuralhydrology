# Three-Candidate Automatic Research Rehearsal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Execute this plan inline in the current session. Do not delegate work to subagents.

**Goal:** Demonstrate one auditable automatic-research loop that proposes, materializes, executes, validates, and development-ranks exactly three structurally different candidates on the frozen eight-basin development package.

**Architecture:** Add a frozen proposal policy that selects three distinct approved method families before any result is read. Materialize each proposal through the existing restricted candidate runtime, run forward and reverse training and prediction, then apply a preregistered development-only recommendation rule. Persist exclusive proposal, result, access, and hash evidence beneath one new output root.

**Tech Stack:** Python 3.11, NumPy 1.26.4, pandas 2.2.3, PyArrow 17.0.0, pytest, restricted Python audit hooks, Slurm central-processing-unit job, SHA-256 manifests.

## Global Constraints

- Use exactly the eight identifiers in `development_basins_v1.json`.
- Propose exactly three candidates from distinct approved method families before reading their development scores.
- Use seed 29 for every candidate and the frozen cluster dependency set.
- Run exactly twelve registered processes: forward and reverse training and prediction for each candidate.
- Prediction may read only weather forcing, static attributes, and the candidate's model artifact; it may not read observed discharge.
- Recommend at most one candidate, using only the two development validation protocols.
- Do not read, search, enumerate, or score the sealed period from 1989-10-01 through 1999-09-30.
- Do not run `src/fair_benchmark/score.py`, a 64-basin or 531-basin formal search, or claim baseline outperformance.
- Do not weaken the sandbox, modify the shared cluster environment, overwrite prior output, or clean logs.
- Stop after the first failed Slurm experiment attempt and preserve its evidence.

---

### Task 1: Freeze and test the proposal contract

**Files:**
- Create: `src/unified_autoresearch/protocols/automatic_rehearsal_v1.json`
- Create: `src/unified_autoresearch/workflow/automatic_rehearsal.py`
- Create: `src/unified_autoresearch/tests/test_automatic_rehearsal.py`

**Interfaces:**
- Consumes: approved candidate catalog and an exact candidate budget of three.
- Produces: an immutable proposal registry with three unique categories, stable identifiers, hypotheses, information declarations, seed, and selection rule.

- [x] **Step 1: Write failing tests for cardinality, uniqueness, forbidden result-dependent proposal inputs, and exclusive output.**
- [x] **Step 2: Implement deterministic proposal validation and exclusive proposal-registry persistence.**
- [x] **Step 3: Verify invalid policies fail before creating an output directory.**

### Task 2: Implement the twelve-process closed loop

**Files:**
- Modify: `src/unified_autoresearch/workflow/automatic_rehearsal.py`
- Create: `src/unified_autoresearch/scripts/run_automatic_rehearsal.py`
- Modify: `src/unified_autoresearch/tests/test_automatic_rehearsal.py`

**Interfaces:**
- Consumes: frozen eight-basin package, proposal policy, resource snapshot, and frozen dependency declaration.
- Produces: three isolated candidate roots, twelve registered runtimes, six development score reports, three summaries, and one development recommendation.

- [x] **Step 1: Write failing orchestration tests for exactly three candidates and twelve successful registered processes.**
- [x] **Step 2: Reuse the existing single-candidate workflow without changing the sandbox or data contract.**
- [x] **Step 3: Preregister development ranking as median mean Nash-Sutcliffe efficiency across the eight common basin cells, with candidate identifier as a deterministic tie-break.**
- [x] **Step 4: Require finite outputs, zero denied events, complete output contracts, and at most one recommendation.**

### Task 3: Verify locally and freeze a cluster source snapshot

**Files:**
- Review: all changed source and test files.
- Create: one source commit only after directed tests pass.

**Interfaces:**
- Consumes: the new tests and existing candidate/runtime tests.
- Produces: a clean commit whose exact SHA-256-relevant source can be checked on the cluster.

- [x] **Step 1: Run the new focused tests locally.**
- [x] **Step 2: Run existing candidate and workflow regression tests locally.**
- [x] **Step 3: Review the diff for sealed-evaluation, scoring-service, and sandbox changes; require none.**
- [x] **Step 4: Commit and push the verified source so the cluster can fetch the exact revision.**

### Task 4: Execute one cluster rehearsal

**Files:**
- Create: a new exact-sequence Slurm script in the `autoresearch-64` mailbox channel.
- Create: a unique cluster attempt root under `/data1/home/sunyiq/autoresearch64/runs/unified_autoresearch/`.

**Interfaces:**
- Consumes: the previously verified eight-basin development package and exact source commit.
- Produces: one Slurm job containing the twelve registered candidate processes and independent evidence checks.

- [x] **Step 1: Verify the source revision, package manifest, eight-basin count, allowed dates, and absent output root before submission.**
- [x] **Step 2: Submit one central-processing-unit Slurm job; run all three candidates sequentially under independent resource monitoring.**
- [x] **Step 3: Run the complete unified-auto-research test suite on the cluster snapshot.**
- [x] **Step 4: Stop after the first packaging failure; retry only after the user's explicit repair instruction, with one changed infrastructure factor and a new output root.**

### Task 5: Independently verify and report the promotion decision

**Files:**
- Create: `evidence/REHEARSAL_EVIDENCE.json` under the unique cluster attempt root.
- Create: `evidence/MANIFEST.sha256` under the unique cluster attempt root.

**Interfaces:**
- Consumes: raw runtime results, access logs, predictions, development scores, and proposal registry.
- Produces: a GO or HOLD decision for this rehearsal and, at most, one candidate proposed for a later 64-basin validation.

- [x] **Step 1: Independently recount three candidates, twelve runtimes, six score reports, and forty-eight candidate-protocol-basin metrics.**
- [x] **Step 2: Independently require process and normalized exit codes zero, output contracts complete, and denied-event count zero for every runtime.**
- [x] **Step 3: Recompute the preregistered development ranking from raw score reports and compare it with the loop recommendation.**
- [x] **Step 4: Hash every attempt artifact and verify the manifest.**
- [x] **Step 5: Report the exact limitation: this proves closed-loop operation, not scientific novelty or baseline superiority.**

## Verified Outcome

- Source commit: `65b31c823e5368e202215cf1c4d9d52a286a547c`.
- First cluster job `202551` stopped before tests because Git archive conversion changed two frozen files from CRLF to LF bytes. Its failed root remains preserved.
- The user then explicitly requested repair. The only changed retry factor was snapshot serialization: the replacement payload retained the preregistered Windows bytes and hashes of the static-attribute table and basin list.
- Retry job `202556` completed on `icn201` with exit code `0:0` in 10 minutes 52 seconds.
- Complete Linux test gate: 299 collected, 291 passed, 8 skipped, 0 failed, 0 errors.
- Experimental cardinality: 3 candidates, 12 registered train/predict runtimes, 6 score reports, 48 protocol-basin metrics, and 24 two-protocol basin cells.
- All 12 process exit codes and normalized exit codes were zero; all 12 required-output contracts were complete; independently counted denied events were zero.
- Independently recomputed median two-protocol development Nash-Sutcliffe efficiencies were `0.33826309576997576` for HBV-lite, `0.0504941725368995` for fusion, and `-0.17988407821406893` for the multilayer perceptron.
- Development-only recommendation: `hbv-lite-calibrated-v1`. This is only a recommendation for a later 64-basin validation, not a baseline-outperformance or scientific-novelty claim.
- Evidence root: `/data1/home/sunyiq/autoresearch64/runs/unified_autoresearch/automatic_rehearsal_8x3_20260811_seq59`.
- Evidence summary SHA-256: `7bb8d23ea03b0cffc0390c4fb6993fd2f6449cc65a47d1674771971a241a723e`.
- Complete 810-entry manifest SHA-256: `c000f729125676a4adc7a2097f38bacda4873a5fa10dcbafc13082734abd5a46`; independent `sha256sum -c` verification passed.
