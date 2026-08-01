# Historical Continuous Multiscale Model Version 09 Complete Input Seal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement, test, and independently audit code that can later seal the complete Maurer meteorological forcing, 27 static attributes, and the already sealed training targets for all 531 basins without opening any raw discharge source.

**Architecture:** A frozen input contract binds the current version 09 protocol, basin list, static table, and the audited target bundle. A streaming builder reads one Maurer file and one target basin at a time into memory-mapped arrays, computes training-only normalization, audits a temporary directory, and atomically promotes it only when a separate one-time production authorization and a task-specific resource gate both pass. Synthetic entry points use the same core functions but are structurally unable to write below the formal result tree.

**Tech Stack:** Python 3.10+, NumPy, pandas, pytest, standard-library JSON/CSV/hash/path/file-lock utilities, existing version 09 task-specific host-memory gate.

## Global Constraints

- [x] Do not create `results/26_historical_band_experts/formal_v09/input_attempt_01` or its `.building` directory in this implementation phase.
- [x] Do not create or consume a production authorization receipt.
- [x] Do not train, generate predictions, draw the formal random split, call scoring, or read formal evaluation observations.
- [x] Do not modify `src/fair_benchmark/frozen/`, the old scoring route, the basin list, the static table, or the two existing target artifacts.
- [x] Keep every current protocol authorization field and `formal_evaluation_target_access` equal to `false`.
- [x] Treat the audited target CSV and target manifest as immutable sources with SHA-256 values `6abadf7172f1c8ebd48122a8abf68985d7d4f94b8c894371270208eeb45f2ebb` and `3061d548fa0b9c81c8e3e25f0dbdd8cfbdb347aaea965ac6f6400c5f09da13e8`.
- [x] New production-source modules must not contain or construct a path to raw discharge. The target CSV is the only supervised-data source.
- [x] Maurer columns are exactly `PRCP(mm/day)`, `Tmin(C)`, `Tmax(C)`, `SRAD(W/m2)`, and `Vp(Pa)` in that order.
- [x] Static input columns are the 27 names sorted alphabetically, matching the historical core data loader's effective `sort_index(axis=1)` order rather than the YAML listing order.
- [x] Static center and scale are computed in `float64` over the 531 basins with sample standard deviation `ddof=1`; normalized statics are cast once to `float32`.
- [x] Dynamic and discharge center and scale are computed only from `1999-10-01` through `2008-09-30` with population standard deviation `ddof=0`.
- [x] Preserve and report the frozen `Tmin(C) == Tmax(C)` condition; do not repair it.
- [x] Use a memory-mapped forcing array and one-basin streaming. Full forcing or target tabular materialization is forbidden.
- [x] Use a task-specific analytical working-set estimate, safety factor `1.25`, serial execution, and reserves of at least 2 GiB physical memory and 2 GiB Windows commit headroom.

---

## Task 1: Freeze the complete-input contract

**Files:**
- Create: `src/26_historical_band_experts/formal_input_contract_v09.py`
- Test: `src/26_historical_band_experts/tests/test_formal_input_contract_v09.py`

- [x] Write failing tests for exact protocol hashes, basin/static/target hashes, periods, shapes, column order, formal output paths, and all authorization fields remaining closed.
- [x] Add immutable contract constants and `validate_formal_input_contract_v09()`.
- [x] Validate the 531-entry Maurer source inventory by filtering only `kind == "maurer"` records from the already audited target manifest; require one record per basin in basin-file order and ignore every non-Maurer record.
- [x] Require the static source payload to reproduce raw `float64` SHA-256 `6c59dcad191e71bf5f7acabb91f7117882d7d1f6736be4d94193921c57dc60a3` and normalized `float32` SHA-256 `aa53d1d06247b246f5557efe6761b9b7becd2be3a680f99d667d2e3c89b9b37a` when the production contract is audited.
- [x] Run `pytest src/26_historical_band_experts/tests/test_formal_input_contract_v09.py -q`.

## Task 2: Implement deterministic artifact primitives

**Files:**
- Create: `src/26_historical_band_experts/artifact_v09.py`
- Test: `src/26_historical_band_experts/tests/test_artifact_v09.py`

- [x] Write failing tests for chunked file SHA-256, contiguous array-payload SHA-256, canonical JSON SHA-256, strict atomic JSON writes, exact file inventories, source-tree manifests, and non-overwriting directory promotion.
- [x] Implement only deterministic standard-library and NumPy helpers; reject symbolic links/reparse points and non-finite JSON numbers.
- [x] Ensure production helpers never overwrite an existing final or temporary artifact.
- [x] Run `pytest src/26_historical_band_experts/tests/test_artifact_v09.py -q`.

## Task 3: Implement one-time complete-input authorization

**Files:**
- Create: `src/26_historical_band_experts/formal_input_authorization_v09.py`
- Test: `src/26_historical_band_experts/tests/test_formal_input_authorization_v09.py`

- [x] Write failing tests for exact action, one-attempt limit, contract/protocol/target/source-tree binding, approval text/hash binding, atomic consumption, replay rejection, and receipt tampering.
- [x] Make receipt construction a callable facility only; this phase must not call it with a production path or write a production receipt.
- [x] Require a future approval sentence that explicitly authorizes complete-input generation while keeping training, prediction, and scoring closed.
- [x] Ensure the production builder accepts no flag that bypasses receipt validation.
- [x] Run `pytest src/26_historical_band_experts/tests/test_formal_input_authorization_v09.py -q`.

## Task 4: Implement task-specific resource estimation and runtime capability

**Files:**
- Create: `src/26_historical_band_experts/formal_input_resources_v09.py`
- Test: `src/26_historical_band_experts/tests/test_formal_input_resources_v09.py`

- [x] Write failing tests for the analytical formula, evidence hash, 1.25 safety factor, 2 GiB physical and commit reserves, serial lock, entry recheck, chunk checkpoints, and unsafe-host rejection before callback.
- [x] Estimate only the actual streaming working set: fixed interpreter/data-frame overhead, one Maurer basin, one target basin, static arrays, hash buffers, and serialization buffer. Do not count memory-mapped file size as resident memory.
- [x] Expose a non-constructible runtime capability required by the formal output context.
- [x] Keep synthetic helpers independent of live host state while testing the same estimate validation logic.
- [x] Run `pytest src/26_historical_band_experts/tests/test_formal_input_resources_v09.py -q`.

## Task 5: Implement streaming Maurer, static, and target stores

**Files:**
- Create: `src/26_historical_band_experts/formal_input_sources_v09.py`
- Test: `src/26_historical_band_experts/tests/test_formal_input_sources_v09.py`

- [x] Write failing tiny-fixture tests for exact Maurer headers, unique dates, fixed period slicing, five-column order, finite values, before/after source hashes, source inventory order, and `Tmin == Tmax` reporting.
- [x] Write failing static tests for exact source columns, basin coverage/order, alphabetical semantic order, `float64` raw values, `ddof=1`, zero-scale rejection, and the cast-once normalized output.
- [x] Write failing target tests for exact CSV columns/order, basin/date coverage, nonnegative finite values, streaming one basin at a time, and absence of any date outside the training period.
- [x] Production source resolution must use only the canonical `basin_mean_forcing/maurer` root and exact relative paths already recorded in the audited target manifest.
- [x] Run `pytest src/26_historical_band_experts/tests/test_formal_input_sources_v09.py -q`.

## Task 6: Implement the atomic builder and sealed loader

**Files:**
- Create: `src/26_historical_band_experts/formal_input_v09.py`
- Create: `src/26_historical_band_experts/build_formal_inputs_v09.py`
- Test: `src/26_historical_band_experts/tests/test_formal_input_v09.py`
- Test: `src/26_historical_band_experts/tests/test_build_formal_inputs_v09.py`

- [x] Write failing tests for the exact artifact set: `basins.txt`, `dates.npy`, `target_dates.npy`, `forcing.npy`, `statics_raw.float64.npy`, `statics.npy`, `targets.npy`, `scaler.json`, `forcing_manifest.json`, `environment.json`, `manifest.json`, `input_audit.json`, and `seal.json`.
- [x] Build arrays through `numpy.lib.format.open_memmap`; verify every chunk checkpoint and flush before hashing.
- [x] Record array dtype, shape, payload hash, whole-file hash, scientific column order, source hashes, contract hash, source-code tree hash, resource evidence hash, and authorization consumption hash.
- [x] Audit the `.building` directory before a single atomic promotion to `input_attempt_01`; never overwrite or merge directories.
- [x] The sealed training loader may return forcing, normalized statics, targets, dates, target dates, basins, and scaler only. It must never return the raw static array.
- [x] The public command must require the fixed protocol, fixed production authorization location, fixed final output, and live resource runtime. Importing it or invoking `--help` must make no writes.
- [x] Synthetic tests must use `tmp_path` and a distinct synthetic builder that rejects every path below `results/26_historical_band_experts/formal_v09`.
- [x] Run both focused test files.

## Task 7: Implement independent pre-promotion and post-seal audit

**Files:**
- Create: `src/26_historical_band_experts/audit_formal_inputs_v09.py`
- Test: `src/26_historical_band_experts/tests/test_audit_formal_inputs_v09.py`

- [x] Reopen every artifact from disk and recompute inventory, file hashes, array payload hashes, dtype/shape, basin/date order, finite values, target range, all scaler statistics, static precision order, source inventory binding, and known temperature equality.
- [x] Scan production source modules for prohibited observed-flow interfaces and reject any hit; keep the scanner's prohibited names derived from the frozen protocol rather than embedding an alternate data path in the builder.
- [x] Require the existing target files and every current authorization field to remain unchanged and closed.
- [x] Make post-seal audit read-only and idempotent; never rewrite `seal.json` or any artifact.
- [x] Run `pytest src/26_historical_band_experts/tests/test_audit_formal_inputs_v09.py -q`.

## Task 8: Regression, independent review, and commit

**Files:**
- Modify only if evidence requires: the new files above and this plan.
- Create: `docs/technical/historical_multiscale_formal_v09_complete_input_code_audit_2026-08-01.md`

- [x] Run a token scan proving the new production builder/source/loader modules contain no raw-discharge access interface.
- [x] Run all newly added tests serially, then the affected version 09 regression subset under the task-specific memory rule.
- [x] Recompute both existing target artifact hashes and list the formal result directory; require exactly the two existing files and no temporary paths.
- [x] Review all new code against this plan, exercise at least one tampering case per layer, and record facts, unknowns, GO/NO-GO, and the exact later authorization condition.
- [x] Commit only after tests and review pass. Do not create the production authorization, complete input package, training outputs, predictions, or scores.
