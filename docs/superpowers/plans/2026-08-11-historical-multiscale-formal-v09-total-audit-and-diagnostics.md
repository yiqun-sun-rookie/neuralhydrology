# Historical Multiscale Formal Version 09 Total Audit and State Diagnostics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the evidence-only closeout of the 24 historical multiscale formal version 09 training runs: independently
recompute their integrity, produce the pre-registered history-state diagnostics for the eight continuous-history runs without
reading any discharge target, reproduce those diagnostics in a second process, and write the final training seal only after
all checks pass.

**Architecture:** Keep sealed run directories immutable. A training auditor reads and rehashes all 24 run trees and reloads
their epoch-30 checkpoints; a target-free diagnostics driver reads only the sealed Maurer meteorological predictors, static
attributes, and continuous-history checkpoints; a separate replay auditor recomputes the same arrays on the same device and
compares raw-array and NumPy-file hashes. Only reports outside run directories are writable. A final sealer binds every
upstream artifact and explicitly records that no formal prediction or official score exists.

**Tech Stack:** Python 3.11, PyTorch, NumPy, pytest, Slurm, the existing `artifact_v09.py` canonical JSON and SHA-256 helpers,
and the existing local Git mailbox for the only high-performance-computing-cluster communication channel.

## Global Constraints

- Work only in `G:/github/pycharm/projects/neuralhydrology/.worktrees/historical-band-experts-pilot` locally.
- Preserve the untracked user handoff `docs/plans/2026-08-11-id26-v09-main-training-near-completion-handoff.md`.
- Do not modify the frozen protocol, run order, input seal, source seal, environment seal, or strict-stage evidence,
  completed run directories, checkpoint files, or any existing generated result.
- Do not open or hash training target arrays in state diagnostics. Do not open formal evaluation observations anywhere.
- Do not run the recent-input path or discharge-output head during state diagnostics.
- Do not generate formal-period predictions, call the scoring service, inspect the secret 107-basin holdout, or select a model.
- Do not overwrite or delete failed outputs. A retry, if required, uses a new isolated attempt directory.
- Preserve the frozen high-performance-computing checkout and result root. New code runs from a separate audit checkout.
- The external audit and state-diagnostic reports stay outside all sealed run directories.
- The training seal is the last artifact. It is forbidden until the 24-run audit and independent state replay both pass.

## Verified Production Evidence Gap

- The original four-workload GPU check is preserved only in Slurm job `201775` output. It reports four workloads, eight
  fresh worker processes, identical results, and a maximum reserved device memory of 1,610 MiB.
- The required canonical `training_resource_preflight.external_audit.json` was never written. The retained log also does
  not persist the individual numeric-array hashes, history-state array hash, or the two TensorFloat-32 switch values.
- Continue through the 24-run audit and both state-diagnostic processes. Do not write or submit the final training seal on
  the current evidence. The final sealer must refuse this missing pre-training artifact rather than recreate it after
  training or treat the log summary as equivalent.

---

### Task 1: Add adversarial tests for the 24-run training audit

**Local status:** Completed.

**Files:**
- Create: `src/26_historical_band_experts/tests/test_audit_formal_training_v09.py`
- Create: `src/26_historical_band_experts/audit_formal_training_v09.py`

- [ ] **Step 1:** Build fixture factories for a minimal sealed run suite with three model families per seed, checkpoint epochs
      10, 20, and 30, canonical manifests, run seals, finite tensors, and a fixed run order. Keep fixture sizes small while
      retaining the production schemas and identity fields.
- [ ] **Step 2:** Add a happy-path unit test for
      `audit_training_run_v09(run_root, expected_spec, input_seal, source_seal)` that requires exact file inventory, all bound
      hashes, 30 epochs, 204,630 optimizer steps, the expected parameter count, finite losses and tensors, a recorded history
      gradient for continuous-history models, and checkpoint epochs 10/20/30.
- [ ] **Step 3:** Parameterize mutations that must fail: missing or extra files; identity, model family, seed, parameter-count,
      epoch-count, or step-count drift; non-finite losses or checkpoint tensors; failure receipts; memory-limit failures;
      missing history gradient; input/source/environment/run-order hash drift; preflight-process reuse; and any
      formal validation, formal prediction, observation, or score artifact.
- [ ] **Step 4:** Add suite-level tests requiring exactly 24 distinct ordered runs, eight seeds per family, identical per-seed
      permutation hashes across the three families, identical initial dropout-state hashes, a post-construction dropout reset,
      and epoch 30 as the only checkpoint eligible for formal prediction.
- [ ] **Step 5:** Add tests that refuse an audit report inside a run directory, refuse a pre-existing training seal, and never
      overwrite a pre-existing report.
- [ ] **Step 6:** Run the new test file and confirm collection fails because `audit_formal_training_v09.py` does not exist.

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_audit_formal_training_v09.py -q
```

Expected: FAIL on the missing implementation.

### Task 2: Implement checkpoint-complete training audit

**Local status:** Completed. The report also binds the independent auditor source tree and records the missing canonical
four-workload preflight report as a pre-seal blocker.

**Files:**
- Create: `src/26_historical_band_experts/audit_formal_training_v09.py`
- Modify: `src/26_historical_band_experts/tests/test_audit_formal_training_v09.py`

- [ ] **Step 1:** Implement strict path and schema helpers using `Path.resolve()`, canonical JSON loading, exact tree inventory,
      and SHA-256 recomputation. Reject symlinks, files outside the run root, unknown schemas, duplicate relative paths, and
      reports located beneath a sealed run.
- [ ] **Step 2:** Implement
      `audit_training_run_v09(run_root, expected_spec, input_seal, source_seal) -> dict`. Recompute every sealed file hash,
      validate all manifest bindings, load checkpoints with `torch.load(..., map_location="cpu", weights_only=False)`, require
      exactly the registered model and optimizer structures, check every tensor with `torch.isfinite`, rebuild the expected
      model with `build_model_v09`, load the epoch-30 state strictly, and verify the exact parameter count.
- [ ] **Step 3:** Mark checkpoint epochs 10 and 20 with `not_eligible_for_formal_prediction=true`; mark epoch 30 as the sole
      eligible source. Do not invoke any model forward method or data loader.
- [ ] **Step 4:** Implement
      `audit_training_suite_v09(formal_root, run_order, report_path) -> dict`. Require the frozen 24-item order, compare
      same-seed permutation and dropout evidence across all three families, bind the protocol/input/source/environment/
      strict-stage hashes, reject premature downstream artifacts, and write the report atomically only after all
      runs pass.
- [ ] **Step 5:** Add a no-argument command-line entry that resolves repository-owned production paths, revalidates the frozen
      run-order file, and prints only the completed report path and canonical report SHA-256.
- [ ] **Step 6:** Run the training-audit tests until all pass, then run `python -m compileall` on the implementation.

### Task 3: Add target-free formal state-diagnostics tests

**Local status:** Completed.

**Files:**
- Modify: `src/26_historical_band_experts/tests/test_state_diagnostics_formal_v09.py`
- Modify: `src/26_historical_band_experts/state_diagnostics_formal_v09.py`

- [ ] **Step 1:** Add a fake sealed-predictor fixture exposing basin order, meteorological dates, 3,288 target dates, forcing,
      static attributes, normalization scalers, and binding hashes, but no target member and no target path.
- [ ] **Step 2:** Test causal index mapping: each frozen target-date index must map to the matching predictor date, every input
      window must end on that date, and batch order must remain basin-major then date-major.
- [ ] **Step 3:** Test checkpoint loading for only the eight `continuous_multiscale_history` runs and epochs 10/20/30. Refuse
      classic or capacity runs, an unregistered seed, missing checkpoint, hash drift, non-finite tensor, or any checkpoint not
      bound by the passed training audit.
- [ ] **Step 4:** Test the batching kernel with a tiny real continuous-history model. Assert it calls only
      `history_states_v09`, never model `forward`, the recent path, or the discharge head; uses a batch size no greater than
      256; and emits little-endian contiguous `int32[samples,2]` keys and `float32[samples,5]` states.
- [ ] **Step 5:** Test
      `write_history_state_diagnostics_v09(input_root, formal_root, run_order, output_root, device) -> dict` with dependency
      injection for the predictor loader and checkpoint loader. Require three fixed-panel arrays per seed, one full-training
      array at epoch 30, eight seed directories, provenance hashes, zero target and observation reads, and no writes beneath a
      run directory.
- [ ] **Step 6:** Run the expanded diagnostics tests and confirm the missing formal driver tests fail before implementation.

### Task 4: Implement the formal diagnostics driver

**Local status:** Completed, including explicit NVIDIA driver, Python, NumPy, device capability, device-memory, and
determinism-switch provenance.

**Files:**
- Modify: `src/26_historical_band_experts/state_diagnostics_formal_v09.py`

- [ ] **Step 1:** Load predictors only through `load_sealed_bridge_inputs_v09`; never call the formal training loader and never
      construct, stat, open, or hash `targets.npy`. Revalidate predictor bindings before and after computation.
- [ ] **Step 2:** Set deterministic PyTorch behavior and record device/runtime evidence: deterministic algorithms enabled,
      CuDNN benchmarking disabled, CuDNN deterministic mode enabled, TensorFloat-32 disabled, and the required CUDA workspace
      configuration present before CUDA initialization.
- [ ] **Step 3:** Map target dates into the predictor date axis with exact equality. Use `gather_causal_windows_v09`,
      `normalize_forcing_batch_v09`, and `split_windows_v09` in batches of at most 256, passing only the history window and
      static attributes to `history_states_v09`.
- [ ] **Step 4:** For epochs 10, 20, and 30, compute the 6,372-row pre-registered panel. At epoch 30 additionally compute all
      1,745,928 training keys. Refuse any non-finite result before writing.
- [ ] **Step 5:** Extend each seed manifest with input-seal, source-seal, environment, run-seal, checkpoint-file, run-order,
      and pre-registration hashes. Write the eight directories atomically under `state_diagnostics/`, never under a run.
- [ ] **Step 6:** Write a root manifest that fixes seed order and every child manifest/directory hash. Add a no-argument
      command-line entry suitable for a single Slurm GPU process.
- [ ] **Step 7:** Run all existing and new diagnostics tests; verify the original array-format contract remains unchanged.

### Task 5: Add and implement independent replay audit

**Local status:** Completed.

**Files:**
- Create: `src/26_historical_band_experts/tests/test_audit_state_diagnostics_formal_v09.py`
- Create: `src/26_historical_band_experts/audit_state_diagnostics_formal_v09.py`

- [ ] **Step 1:** Add tests requiring a second-process audit to revalidate the training audit, predictor seals, run order,
      device/environment identity, eight seed manifests, exact file inventory, array shapes/dtypes/order, finite values, and
      summary statistics recomputed from disk.
- [ ] **Step 2:** Add mutation tests for wrong sample keys, reordered rows, changed raw bytes, changed NumPy headers, changed
      summary statistics, missing/extra seed or file, different checkpoint binding, target/observation reads, recent-path/head
      execution, and a report path inside a diagnostic or run directory.
- [ ] **Step 3:** Implement
      `audit_history_state_diagnostics_v09(input_root, formal_root, run_order, diagnostic_root, report_path, device) -> dict`.
      Recompute diagnostics without creating a persistent replay tree: serialize each replay array with `numpy.save` to an
      in-memory byte stream, compare raw bytes and complete `.npy` bytes, and independently recompute all summaries.
- [ ] **Step 4:** Require identical device and environment hashes and verify predictor bindings before and after replay. Record
      exactly zero target reads, formal-observation reads, recent-path executions, and discharge-head executions.
- [ ] **Step 5:** Write the external report atomically only after all eight seeds pass. Add a no-argument command-line entry for
      a separate Slurm GPU job; never combine producer and auditor in one process.
- [ ] **Step 6:** Run the independent-audit tests until all pass.

### Task 6: Gate and write the final training seal

**Local implementation status:** Completed and tested for a fully compliant fixture. **Production status: HOLD** because
the canonical pre-training four-workload report does not exist and cannot be recreated retrospectively.

**Files:**
- Modify: `src/26_historical_band_experts/tests/test_audit_formal_training_v09.py`
- Modify: `src/26_historical_band_experts/audit_formal_training_v09.py`

- [ ] **Step 1:** Add tests that `seal_training_suite_v09(formal_root, audit_report) -> dict` refuses missing or failed training
      audit, missing or failed state replay audit, any upstream hash drift, any missing run/checkpoint/diagnostic directory,
      premature prediction or score artifacts, a pre-existing seal, and a seal target below a run directory.
- [ ] **Step 2:** Require the seal to bind the protocol, input seal, input external audit, trusted-target-source external audit,
      legacy bridge audit, independent resource preflight, strict run seal and external audit, diagnostics pre-registration,
      executable source tree, environment, run order, all 24 run seals, checkpoints 10/20/30, all eight
      diagnostic directories, diagnostics external audit, and training external audit.
- [ ] **Step 3:** Explicitly record `formal_prediction_generated=false`, `official_score_called=false`, and
      `not_eligible_for_formal_prediction=true` for epochs 10 and 20. Write once with canonical JSON and re-read/re-hash it.
- [ ] **Step 3a:** Do not require or recreate the retired `A09-TRAIN-01` one-use main-training authorization. Its removal was
      approved before execution because a multi-job resumable 24-run suite cannot consume one single-attempt receipt safely.
      The audit instead binds the frozen protocol, sealed inputs, frozen order, exact training Git commit/source tree, resource
      preflight, and the unchanged completed run bytes. Existing strict-stage authorization evidence remains bound indirectly
      through the strict-stage seal and external audit.
- [ ] **Step 4:** Run the three targeted test files together and verify all pass.

Run:

```powershell
pytest src/26_historical_band_experts/tests/test_audit_formal_training_v09.py `
  src/26_historical_band_experts/tests/test_state_diagnostics_formal_v09.py `
  src/26_historical_band_experts/tests/test_audit_state_diagnostics_formal_v09.py -q
```

### Task 7: Local verification, review, and commit

**Verification status before commit:** 46 targeted tests passed; the full idea-local suite has 719 passed and the same two
pre-existing production-state-coupled failures documented in the handoff. Python compilation, `git diff --check`, the
120-character scan, forbidden diagnostic-import scan, and Bash syntax checks all passed. YAPF is not installed locally, so
no formatter command was run.

- [ ] **Step 1:** Run all version-09-related tests and then the complete idea-local suite explicitly, because repository-level
      pytest does not discover `src/26_historical_band_experts/tests` automatically.
- [ ] **Step 2:** Run `python -m compileall` for all changed Python modules, `git diff --check`, a line-length scan at 120
      characters, and a repository search proving no target loader or scoring entry is imported by diagnostics/auditors.
- [ ] **Step 3:** Review every changed line against the pre-registration and Task 6 refusal list. Fix substantiated findings and
      rerun affected tests.
- [ ] **Step 4:** Record any pre-existing unrelated test failures with exact test names and evidence. Do not weaken tests or
      modify frozen production state to make them pass.
- [ ] **Step 5:** Commit only the plan, implementations, tests, and cluster job entries. Do not stage the untracked handoff.

### Task 8: Execute the evidence-only closeout on the cluster

**Execution status:** Pending push and cluster jobs. Steps 2–4 remain authorized. Step 5 is forbidden on the current
production evidence and must remain HOLD even if Steps 2–4 pass.

**Files:**
- Create: `src/26_historical_band_experts/hpc/audit_formal_training_v09.slurm`
- Create: `src/26_historical_band_experts/hpc/state_diagnostics_formal_v09.slurm`
- Create: `src/26_historical_band_experts/hpc/audit_state_diagnostics_formal_v09.slurm`
- Create: `src/26_historical_band_experts/hpc/seal_formal_training_v09.slurm`

- [ ] **Step 1:** Push the verified code commit and use the `id26-v09-strict` Git-mailbox channel to create or update a separate
      audit checkout at the exact commit. Do not move or modify either frozen training checkout.
- [ ] **Step 2:** Submit the CPU/compute training-audit job. After completion, fetch its Slurm state, elapsed time, exit code,
      report path and SHA-256, and the last log lines. Stop if it does not pass.
- [ ] **Step 3:** Submit one GPU diagnostics producer job. Fetch and verify all eight manifests, expected row counts, finite
      counts, zero prohibited reads/executions, exact input/checkpoint bindings, and root manifest hash. Stop if it does not pass.
- [ ] **Step 4:** Submit a separate GPU replay-audit job on the same device class and environment. Fetch its independent report,
      byte-identity counts, environment binding, exit code, and log tail. Stop if it does not pass.
- [ ] **Step 5:** Submit the final CPU/compute seal job only after Steps 2–4 pass. Fetch the training seal and independently
      recompute its SHA-256 plus every bound upstream SHA-256 with lightweight cluster commands.
- [ ] **Step 6:** Copy no large checkpoint or diagnostic array through the mailbox. Archive only bounded JSON summaries, hashes,
      Slurm metadata, and log tails under the designated evidence paths.
- [ ] **Step 7:** Report facts, inference, and unknowns separately. The continuation boundary after a valid training seal is
      formal prediction generation; do not cross it without a new explicit decision.

## Completion Criteria

- All 24 training runs pass a full independent tree and checkpoint audit.
- All eight continuous-history runs have epoch-10/20/30 fixed-panel diagnostics and epoch-30 full-training diagnostics.
- A separate process reproduces every key array and every five-column state array byte-for-byte on the bound device/environment.
- `training_external_audit.json`, `state_diagnostics_external_audit.json`, and `training_seal.json` exist outside run directories,
  have canonical hashes, and bind every required upstream artifact.
- No training target is accessed by diagnostics; no formal observation, prediction, scoring, cleanup, or model selection occurs.
- Local tests, cluster job states, report hashes, and evidence paths are sufficient for a fresh reviewer to reproduce the closeout.
- If the canonical pre-training resource report remains absent, completion stops after independent state replay with a
  documented HOLD; `training_seal.json` must not be created.
