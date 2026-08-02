# Historical Multiscale Formal Version 09 Strict Prerequisite Entry Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add one closed, resumable production entry that creates and validates the two missing prerequisite reports for the seed-100 strict-nesting stage without creating authorization or launching training.

**Architecture:** Keep the existing immutable input seal, classic checkpoints, and strict training launcher unchanged. A no-argument production entry resolves fixed paths, rejects any existing stage authorization, consumption receipt, or training output, loads only target-free sealed predictor inputs, reuses the existing legacy-checkpoint bridge, samples live host and accelerator resources, writes reports atomically, and validates both reports against the current protocol before returning their hashes.

**Tech Stack:** Python 3.11, PyTorch, NumPy memory maps, pytest, SHA-256, atomic JSON files, Git.

## Global Constraints

- Work only in `G:/github/pycharm/projects/neuralhydrology/.worktrees/historical-band-experts-pilot`.
- Use only Maurer forcing and the frozen 27 static attributes.
- Do not read formal evaluation observations, flow targets, old score files, or scoring answer keys.
- Do not create a training-stage authorization or consumption receipt and do not launch training, prediction, or scoring.
- Do not overwrite either prerequisite report. A valid existing report may be reused; an invalid or unexpected report must stop the entry.
- Keep the fixed stage identifier `R09-NEST-S100`, seed `100`, device `cuda:0`, classic result root `results/18_lstm_fair_531`, and formal report paths already frozen by `strict_stage_paths_v09()`.
- Preserve a clean Git worktree, fail on path links or Windows directory junctions, and write JSON atomically.

---

### Task 1: Test the closed preparation contract

**Files:**
- Create: `src/26_historical_band_experts/tests/test_prepare_formal_strict_stage_v09.py`
- Modify: `src/26_historical_band_experts/tests/test_run_formal_strict_stage_v09.py`

**Interfaces:**
- Consumes: fixed `StrictStagePathsV09`, protocol, sealed inputs, classic checkpoint root, live resource samplers.
- Produces: failure-first tests for fixed paths, no-authorization behavior, resumability, report validation, and atomic publication.

- [x] **Step 1: Write tests that reject stage authorization, consumption, output, linked paths, invalid existing reports, and any callback override in the public entry.**
- [x] **Step 2: Write tests proving a missing bridge report is generated once, a valid report is reused, every actual bridge gets a live resource check, no authorization file is created, and returned hashes equal the final files.**
- [x] **Step 3: Write tests proving strict launch rejects a resource report whose estimate, safe fields, action, variant, authorization flag, exact JSON type, or input binding differs from the current protocol.**
- [x] **Step 4: Run focused failure-first and regression tests for the closed preparation contract.**

### Task 2: Implement production preparation and stronger launch validation

**Files:**
- Create: `src/26_historical_band_experts/prepare_formal_strict_stage_v09.py`
- Modify: `src/26_historical_band_experts/run_formal_strict_stage_v09.py`

**Interfaces:**
- Produces: `prepare_formal_strict_stage_v09() -> dict`, a no-argument production entry.
- Produces: `_validate_resource_preflight_report_v09(report, protocol) -> None`.

- [x] **Step 1: Implement fixed-path resolution and reject any authorization, consumption receipt, training output, dirty Git state, linked path, or unexpected temporary path before opening model or array artifacts.**
- [x] **Step 2: Load target-free predictor inputs through the frozen seal and audits; generate or validate the legacy bridge against all eight registered checkpoints and the fixed real training-input panel.**
- [x] **Step 3: Run the read-only live resource preflight under the global lease, require current host and device-0 gates before every actual bridge, and atomically publish or validate the fixed resource report.**
- [x] **Step 4: Recompute all strict prerequisite hashes, return a compact preparation receipt with `training_authorization_created: false`, and expose only a no-argument command-line entry.**
- [x] **Step 5: Strengthen strict launch to revalidate input bindings, resource arithmetic, protocol binding, safety flags, exact JSON types, and `authorization_checked: false` before accepting hashes.**

### Task 3: Verify, review, and commit

**Files:**
- Test: the new preparation tests plus the existing artifact, input-loader, resource, authorization, strict-launch, and legacy-bridge tests.

- [x] **Step 1: Run focused tests, then the complete affected regression set serially.**
- [x] **Step 2: Run `python -m compileall` on changed modules and `git diff --check`.**
- [x] **Step 3: Perform an independent read-only code review focused on forbidden reads, authorization boundaries, resource validation, path links, restart behavior, and report overwrite behavior.**
- [x] **Step 4: Fix all substantiated findings, rerun affected tests, and commit all verified code and plan changes.**

## Stopping Conditions

Stop without creating or changing formal evidence if any immutable hash drifts, the worktree is dirty at production preparation, a linked path is found, a prerequisite report already exists but fails validation, live resource reserves fail, any legacy prediction differs, any target value or formal evaluation observation is read, or any training authorization, consumption receipt, or output directory exists.

## Self-Review

- Spec coverage: the plan closes the missing production path between target-free sealed predictors and a future one-use strict-training authorization.
- Boundary coverage: preparation can create only the two fixed prerequisite reports; it cannot create authorization or call the training function.
- Failure coverage: partial valid evidence is resumable, invalid evidence is never overwritten, and launch independently revalidates report content rather than trusting only its file hash.
- Placeholder scan: no scientific choice, path, seed, model, device, or stopping condition remains unspecified.
