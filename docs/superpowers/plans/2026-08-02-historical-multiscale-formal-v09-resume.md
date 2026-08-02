# Historical Multiscale Formal Version 09 Pre-Score Resume Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resume formal version 09 from the already sealed 531-basin inputs, implement and independently verify the missing training and prediction pipeline, then stop with three sealed prediction sets before any official scoring call.

**Architecture:** Keep the existing scientific protocol and sealed inputs immutable. Add a stage-scoped one-use authorization layer, a read-only memory-mapped training loader, strict lockstep reproduction, 24 serial main runs, post-training state diagnostics, and deterministic prediction sealing. Every high-load entry uses the current action-specific analytical resource estimate with a 1.25 safety factor and retains 2 GiB of physical and committed-memory headroom plus 1 GiB of accelerator memory.

**Tech Stack:** Python 3.11, PyTorch, NumPy memory maps, pandas, psutil, pytest, Git, SHA-256, PowerShell.

## Global Constraints

- Work only in `G:/github/pycharm/projects/neuralhydrology/.worktrees/historical-band-experts-pilot` on branch `codex/historical-band-experts-pilot`.
- Use only the five named Maurer daily forcing columns and the frozen 27 static attributes as model inputs.
- Keep the formal evaluation observations inaccessible. Do not read `usgs_streamflow`, `camels_hydro`, `*_obs_eval.parquet`, or any scoring answer key.
- Do not modify `src/fair_benchmark/frozen/`, `src/fair_benchmark/score.py`, the old scoring implementation, basin lists, split files, the sealed training target bundle, or `input_attempt_01`.
- Treat `results/26_historical_band_experts/formal_v09/input_attempt_01/seal.json` SHA-256 `a5a64e43312ac303bf03ea3840e2cf126563527c6b82b8b94035c34978c25b3a` and sealed-file digest `c4252458c7c42ba2811795bf4e7ec046ab748a8cf67529eb85a68607029210ad` as immutable prerequisites.
- Treat `training_targets.csv` SHA-256 `6abadf7172f1c8ebd48122a8abf68985d7d4f94b8c894371270208eeb45f2ebb` and its manifest SHA-256 `3061d548fa0b9c81c8e3e25f0dbdd8cfbdb347aaea965ac6f6400c5f09da13e8` as immutable prerequisites.
- Keep 531 basins, 3,288 training dates per basin, 1,745,928 training samples, 30 epochs, 6,821 updates per epoch, 204,630 updates per run, batch size 256, and seeds 100 through 800.
- Keep model parameter counts 297,217 for the 256-unit clean classic control, 595,198 for the 369-unit capacity control, and 596,737 for the continuous-history candidate.
- Keep Adam parameters, learning rates, gradient clipping, forget bias, dropout, training loss, sample order, checkpoint epochs, and float64 ensemble order exactly as frozen in `formal_v09_protocol.json`.
- The 2026-07-31 task-specific memory policy supersedes every older fixed 12.68 GiB threshold. Each entry validates a reproducible operation-and-variant estimate, multiplies it by 1.25, runs serially under the global lease, and after the guarded peak retains at least 2 GiB physical memory, 2 GiB committed-memory headroom, and 1 GiB accelerator memory.
- Never materialize the full `1,745,928 x 3,562 x 5` window tensor. Load at most one 256-sample batch.
- Do not compute validation or formal metrics until all 24 runs and all three prediction ensembles are sealed.
- Do not create a one-time scoring authorization, draw the 256-bit formal random value, access evaluation observations, or call the scoring service in this plan.
- Any source or documentation change must pass its focused tests, `git diff --check`, independent read-only review, and a clean commit before formal execution.

---

### Task 1: Persist the already completed input-audit chain

**Files:**
- Reuse: `src/26_historical_band_experts/audit_formal_inputs_v09.py`
- Create generated evidence: `results/26_historical_band_experts/formal_v09/input_attempt_01.external_audit.json`
- Create generated evidence: `results/26_historical_band_experts/formal_v09/input_attempt_01.trusted_source_external_audit.json`

**Interfaces:**
- Consumes the immutable complete-input seal, one-use input authorization and consumption record.
- Produces two directory-external JSON reports whose SHA-256 values can be bound by later stage receipts.

- [ ] **Step 1: Verify the prerequisite hashes without opening all source values**

Run `Get-FileHash -Algorithm SHA256` for the seal, target, target manifest, input authorization, and input consumption record. Refuse any mismatch, `.building` directory, temporary file, or dirty tracked worktree.

- [ ] **Step 2: Run one fresh read-only complete-input audit**

Call `audit_input_directory_v09(..., require_seal=True)` in a fresh process and write its returned mapping atomically outside `input_attempt_01`. The report path must not exist beforehand. This is the single persisted external replay required for training provenance; do not repeat it after success unless a bound file changes.

- [ ] **Step 3: Write the compact trusted-target attestation**

Bind the existing target audit facts: 531 basins, 3,288 dates per basin, 1,745,928 rows, source-file count 1,062, zero source-hash differences, zero evaluation-period parsed flow values, target and manifest hashes, and the audit-producing commit. Do not copy target values into the report.

- [ ] **Step 4: Verify both reports**

Reload both JSON files, require canonical JSON, recompute their SHA-256 values, and confirm `input_attempt_01` itself is unchanged.

---

### Task 2: Implement stage-scoped authorization and sealed training batches

**Files:**
- Create: `src/26_historical_band_experts/stage_authorization_v09.py`
- Modify: `src/26_historical_band_experts/launch_gate_v09.py`
- Create: `src/26_historical_band_experts/formal_training_data_v09.py`
- Create: `src/26_historical_band_experts/tests/test_stage_authorization_v09.py`
- Create: `src/26_historical_band_experts/tests/test_formal_training_data_v09.py`
- Modify: `src/26_historical_band_experts/tests/test_launch_gate_v09.py`

**Interfaces:**
- Produces `validate_stage_authorization_v09(...)`, `consume_stage_authorization_v09(...)`, `load_sealed_training_inputs_v09(...)`, `epoch_order_v09(...)`, `load_training_batch_v09(...)`, and `masked_nse_training_loss_v09(...)`.

- [ ] **Step 1: Add failure-first tests**

Test exact action, scope, allowed-run set, approval text hash, protocol hash, input-seal hash, both external-audit hashes, executable-tree hash, output root, one-use exclusive consumption, and rejection of unknown fields. Test that the loader never exposes or opens `statics_raw.float64.npy`, never opens formal evaluation observations, and returns read-only maps only.

- [ ] **Step 2: Implement one-use stage receipts**

Use distinct scopes for strict nesting, the 24 main runs, and formal prediction sealing. Perform the action-specific resource and current-state checks before exclusive receipt consumption; consume immediately before the first irreversible child-process launch. A failed or interrupted attempt is not reusable.

- [ ] **Step 3: Implement deterministic training keys and normalization**

Generate the 1,745,928 keys from frozen basin order and target-date order. Use `torch.Generator(device='cpu')` with `seed * 1_000_003 + epoch` for each complete permutation. Perform forcing and target normalization in C-contiguous float32 NumPy arrays by explicit subtract-then-divide operations using the sealed float64 statistics converted once to float32.

- [ ] **Step 4: Implement bounded variant-specific batches**

The clean classic, disabled-history, and capacity variants copy only `[batch,270,5]`; the continuous-history variant copies `[batch,3562,5]`, normalizes first, and then calls `split_windows_v09()`. Assert that the recent slice is byte-identical in both paths.

- [ ] **Step 5: Verify and commit**

Run the three focused test files plus `test_bands_formal_v09.py`, format only changed Python files with YAPF, run `git diff --check`, and commit `Feat: Add sealed formal v09 training batches`.

---

### Task 3: Implement full strict nesting and independent replay

**Files:**
- Create: `src/26_historical_band_experts/train_strict_formal_v09.py`
- Create: `src/26_historical_band_experts/audit_strict_formal_v09.py`
- Create: `src/26_historical_band_experts/audit_legacy_checkpoint_bridge_v09.py`
- Create: `src/26_historical_band_experts/tests/test_train_strict_formal_v09.py`
- Create: `src/26_historical_band_experts/tests/test_audit_strict_formal_v09.py`
- Create: `src/26_historical_band_experts/tests/test_audit_legacy_checkpoint_bridge_v09.py`

**Interfaces:**
- Produces a sealed seed-100 strict run and two directory-external read-only audit reports.

- [ ] **Step 1: Add adversarial synthetic tests**

Inject mismatches in active parameter order, batch keys, dropout random state, prediction, loss, unclipped and clipped gradients, gradient norm, Adam state, updated parameters, final streaming predictions, source hashes, and report placement. Each mismatch must fail at the first divergent step.

- [ ] **Step 2: Implement the 30-epoch lockstep runner**

Build the clean 256-unit model and disabled-history model with identical active parameters and explicit Adam settings. Execute all 204,630 paired updates with zero absolute and relative tolerance. Save paired checkpoints at epochs 10, 20, and 30, stream all training-key predictions, and require byte-identical prediction digests and maximum difference zero.

- [ ] **Step 3: Implement legacy function bridging**

For each frozen legacy seed, verify config and epoch-30 checkpoint hashes, load the same six active tensors into the core model, clean classic model, and disabled-history model, then require exact predictions on the frozen synthetic panel and 531-by-12 real training-input panel. Do not read any flow targets or result metrics.

- [ ] **Step 4: Implement independent strict replay**

In a fresh process, rebuild both models from the sealed epoch-30 checkpoints, stream all 1,745,928 training keys, require the two predictions to match exactly, and require each to match the sealed reference within absolute tolerance `1e-6` and relative tolerance zero.

- [ ] **Step 5: Verify and commit**

Run the three new test files plus `test_strict_nesting_formal_v09.py` and `test_models_formal_v09.py`; format, check the diff, independently review, and commit `Feat: Add full formal v09 nesting audit`.

---

### Task 4: Implement resource-calibrated serial main training

**Files:**
- Create: `src/26_historical_band_experts/configs/formal_v09_run_order.json`
- Create: `src/26_historical_band_experts/resource_preflight_formal_v09.py`
- Create: `src/26_historical_band_experts/train_formal_v09.py`
- Create: `src/26_historical_band_experts/run_formal_training_v09.py`
- Create: `src/26_historical_band_experts/tests/test_resource_preflight_formal_v09.py`
- Create: `src/26_historical_band_experts/tests/test_train_formal_v09.py`
- Create: `src/26_historical_band_experts/tests/test_run_formal_training_v09.py`

**Interfaces:**
- Produces `run_resource_preflight_v09(...)`, `run_training_v09(...)`, and `run_training_suite_v09(...)`.

- [ ] **Step 1: Freeze and test the 24-run order**

Use the preregistered balanced order for seeds 100 through 800. Require exactly eight runs per family and three runs per seed, with no missing, duplicate, or reordered run identifiers.

- [ ] **Step 2: Implement independent synthetic resource calibration**

For strict lockstep, clean classic, capacity control, and continuous-history workloads, launch two fresh accelerator child processes serially. Each uses batch 256 and the exact formal shapes for one forward, loss, backward, clipping, and Adam step. Bind measured peak host and accelerator values, analytical upper bounds, deterministic array hashes, device identity, environment, source tree, and exit codes. The measured values may validate but never reduce the frozen analytical upper bound.

- [ ] **Step 3: Implement one-run training**

Reset the dropout stream after model and optimizer construction using `seed * 1_000_003 + 900_001`. Run exactly 30 epochs and 204,630 updates. Save only epochs 10, 20, and 30, mark epoch 30 as the only prediction-eligible checkpoint, record per-epoch permutation hashes, and for the candidate verify nonzero finite gate gradients at step 1 and nonzero finite history-encoder gradients by step 3.

- [ ] **Step 4: Implement serial orchestration and fail-closed recovery**

Launch one isolated child process at a time. Reject any pre-existing final, `.building`, or `.failed` directory. On the first failure, stop all later runs, retain completed sealed runs, and write one immutable failure receipt. Never retry automatically.

- [ ] **Step 5: Verify and commit**

Run the three new test files, format, check the diff, independently review, and commit `Feat: Add serial formal v09 training suite`.

---

### Task 5: Implement post-training diagnostics and total training seal

**Files:**
- Create: `src/26_historical_band_experts/state_diagnostics_formal_v09.py`
- Create: `src/26_historical_band_experts/audit_state_diagnostics_formal_v09.py`
- Create: `src/26_historical_band_experts/audit_formal_training_v09.py`
- Create: corresponding three test files under `src/26_historical_band_experts/tests/`.

**Interfaces:**
- Produces read-only candidate-state diagnostics, an independent byte-identical replay, `training_external_audit.json`, and `training_seal.json`.

- [ ] **Step 1: Add missing, extra, drift, and leakage rejection tests**

Reject any run-count, order, seed, family, parameter, epoch, update, permutation, dropout-state, checkpoint, input, source, environment, authorization, finite-value, state-coverage, replay-hash, or forbidden-access mismatch.

- [ ] **Step 2: Implement preregistered state diagnostics**

After all 24 runs are sealed, read only Maurer forcing, normalized statics, and the candidate checkpoints. Compute the five frozen state quantities on the 531-by-12 panel at epochs 10, 20, and 30 and on all training keys at epoch 30. Do not read targets or run the flow head.

- [ ] **Step 3: Implement byte-identical independent replay**

In a second process, regenerate every diagnostic key and little-endian float32 state array; require exact raw-byte and `.npy` file hashes.

- [ ] **Step 4: Implement the total training audit and seal**

Recompute every run hash tree, validate all 24 epoch-30 checkpoints, bind the strict run and all prerequisite reports, and write the total training seal only after the external audit passes.

- [ ] **Step 5: Verify and commit**

Run all new tests, the complete idea-local suite when current task-specific resources permit, format, check, independently review, and commit `Feat: Add formal v09 training audit`.

---

### Task 6: Execute formal pre-score stages under immutable gates

**Files:**
- Generated: stage authorization and consumption receipts.
- Generated: strict nesting, 24 training runs, state diagnostics, three prediction ensembles, external audit reports, and seals.
- Modify after successful audits: `src/26_historical_band_experts/registry.csv` and new technical audit documents.

**Interfaces:**
- Consumes only committed, independently reviewed code and immutable prerequisites.
- Produces three sealed prediction sets and a pre-score GO or HOLD decision.

- [ ] **Step 1: Execute and audit strict nesting**

Run the one-use seed-100 strict stage only if the current host and accelerator snapshots pass the analytical and calibrated resource gates. Stop on any nonzero lockstep difference or replay difference above `1e-6`.

- [ ] **Step 2: Execute and audit all 24 main runs**

Run serially in frozen order. Do not inspect performance. After all runs finish, execute the state diagnostics, independent replay, total audit, and total training seal.

- [ ] **Step 3: Implement or verify the prediction-sealing code**

Follow `docs/superpowers/plans/2026-07-31-historical-multiscale-formal-v09-prediction-sealing-stage.md`, with the current task-specific resource policy replacing every obsolete fixed-memory threshold. Require exact 531-by-3,652 coverage for each of 24 seed files and all three float64 ensembles.

- [ ] **Step 4: Generate and independently replay all predictions**

Use only epoch-30 checkpoints and sealed evaluation-period Maurer forcing plus normalized statics. Do not open formal observations. Require independent reproduction maximum absolute difference at most `1e-6`, source scan hits zero, and unchanged scoring ledger.

- [ ] **Step 5: Stop before scoring**

Run the clean-pair pre-score auditor against the actual three sealed hashes. Report facts, unknowns, and GO or HOLD. Do not create the one-time scoring authorization, draw the formal random value, access observations, or call the scoring service.

## Stopping Conditions

Stop the entire stage and preserve evidence if any immutable hash drifts; the worktree is dirty at a formal launch; resource reserves fail; deterministic replay fails; strict nesting has any nonzero same-process difference; a run is incomplete or nonfinite; a forbidden input is opened; an output path already exists; an authorization is absent, malformed, or consumed; independent prediction replay exceeds `1e-6`; or the scoring ledger changes before the authorized scoring process.

## Self-Review

- Spec coverage: sealed input provenance, legal training information, strict nesting, all 24 runs, state diagnostics, resource safety, prediction sealing, and the scoring boundary each have one explicit task.
- Resource consistency: no fixed 12.68 GiB gate remains; all high-load work uses the protocol-bound analytical estimate plus current live snapshots and reserves.
- Type and identifier consistency: model variants, experiment identifiers, seeds, epochs, run counts, and artifact names match the current protocol and existing prediction-sealing plan.
- Placeholder scan: the plan contains no deferred scientific choices; every selection rule and stopping boundary is frozen before formal execution.
