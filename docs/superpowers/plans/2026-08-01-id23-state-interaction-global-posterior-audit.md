# State Interaction Global Posterior Audit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Execute this plan inline with test-first development and independent verification. Do not dispatch subagents. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run the frozen same-day state audit that isolates full state-and-covariance interaction versus no state interaction while scoring one global posterior state from each method over all 540 days and all 15 states.

**Architecture:** Reconstruct both three-model assimilation methods from the sealed ideal input package. Use identical parameter candidates, process covariance, forcing, observations, initial states, initial covariance, transition probabilities, and posterior-probability update; change only the state-and-covariance interaction mode. Publish an atomic result package and verify it through a separate script that does not import the production runner or summary module.

**Tech Stack:** Python, NumPy, pytest, JSON, CSV, SHA-256.

## Global Constraints

- Standard full interaction and the no-interaction control each publish one posterior-probability-weighted global posterior after every observation update.
- Model-conditioned subfilter states are diagnostics only and cannot be scored as final method outputs.
- Use all eight matched blocks, three truth trials, 540 assimilation days, and 15 states.
- Execute no forecast and do not group results by time since a staged truth-parameter switch.
- Preserve the sealed source package and all existing result directories byte-for-byte.
- One experiment identifier, one frozen config snapshot, one isolated output directory, and one registry row.

---

### Task 1: Freeze the executable contract

**Files:**
- Modify: `src/hbv_multilead_joint_uncertainty/configs/g3_fixed_process_state_interaction_global_posterior_audit_v01.json`
- Create: `test/test_hbv_state_interaction_global_posterior_audit_runner.py`

- [x] **Step 1: Add failing validation tests for the sealed input hash, interaction modes, all 540 days, all 15 states, no forecast, and one changed factor.**
- [x] **Step 2: Add the sealed source path and SHA-256, transition probability, numerical tolerance, expected array shapes, and `frozen_before_run` status to the config.**
- [x] **Step 3: Run the focused config tests and require them to pass.**

### Task 2: Implement the state statistics

**Files:**
- Create: `src/hbv_multilead_joint_uncertainty/state_interaction_global_posterior_audit.py`
- Create: `test/test_hbv_state_interaction_global_posterior_audit.py`

- [x] **Step 1: Add failing tests for per-state, hydrologic-store, routing-memory, and complete standardized errors using full-minus-none paired differences.**
- [x] **Step 2: Implement the fifteen-state summary and the prespecified interval decisions.**
- [x] **Step 3: Run the focused statistics tests and require them to pass.**

### Task 3: Implement the atomic formal runner

**Files:**
- Create: `src/hbv_multilead_joint_uncertainty/scripts/run_g3_fixed_process_state_interaction_global_posterior_audit.py`
- Modify: `test/test_hbv_state_interaction_global_posterior_audit_runner.py`

- [x] **Step 1: Add failing tests that require exact full-versus-none construction, unique global-posterior storage, unused output protection, and no forecast-module import.**
- [x] **Step 2: Reconstruct both assimilations from the sealed forcing, observations, initial states, covariances, parameter vectors, and process covariance.**
- [x] **Step 3: Write `config_snapshot.json`, `environment.json`, `evidence.npz`, `summary.json`, and `checksums.json` through an atomic staging directory.**
- [x] **Step 4: Run the runner tests and require them to pass.**

### Task 4: Implement independent verification

**Files:**
- Create: `src/hbv_multilead_joint_uncertainty/scripts/verify_g3_fixed_process_state_interaction_global_posterior_audit.py`
- Create: `test/test_hbv_state_interaction_global_posterior_audit_verifier.py`

- [x] **Step 1: Add failing tests that require the verifier to avoid importing the production runner, production summary, and every forecast module.**
- [x] **Step 2: Independently reconstruct both assimilation histories and recompute every saved numerical statistic and decision.**
- [x] **Step 3: Verify source and result checksums and write one immutable `independent_verification.json`.**
- [x] **Step 4: Run the verifier tests and require them to pass.**

### Task 5: Execute and close the experiment

**Files:**
- Modify: `src/hbv_multilead_joint_uncertainty/configs/g3_experiment_registry.csv`
- Modify: `src/hbv_multilead_joint_uncertainty/HANDOFF_20260801_COMPLETE_STATE_PARAMETER_CONTROL.md`
- Create: `docs/plans/2026-08-01-id23-state-interaction-global-posterior-audit-closure.md`
- Update: all related active documentation and authorized memory note if the formal verification passes.

- [x] **Step 1: Run all focused tests before the formal experiment.**
- [x] **Step 2: Run the formal experiment once into its unused registered output directory.**
- [x] **Step 3: Run the independent verifier once and require zero or tolerance-bounded reconstruction differences.**
- [x] **Step 4: Update the registry, handoff, design status, closure, and ambiguity audit using only verified results.**
- [x] **Step 5: Run targeted regression tests, parse every affected config, check source terminology, and record final hashes.**
