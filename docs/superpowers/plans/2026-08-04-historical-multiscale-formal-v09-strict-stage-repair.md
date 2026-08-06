# Historical Multiscale Formal Version 09 Strict-Stage Repair Plan

**Approved scope (2026-08-04):** repair code only. No training, no formal prediction, no scoring.

**Goal:** Make the seed-100 strict-nesting stage executable end to end by (1) fixing the legacy
checkpoint bridge so it addresses the frozen core model with the key names that model actually
requires, and (2) adding the two missing closed production entries that the stage needs but that
never existed: one that mints the one-use `A09-NEST-01` training authorization, and one that runs
the post-training independent replay audit.

**Why this is needed:** the production run of `prepare_formal_strict_stage_v09.py` on
2026-08-04T21:16+08:00 exited 1 with `KeyError: 'PRCP(mm/day)'` raised from
`neuralhydrology/modelzoo/inputlayer.py:234`, on the first two-row synthetic panel of the
seed-100 run, before any real basin data was touched. Separately, `create_stage_authorization_v09`
and `audit_strict_run_v09` are library functions with no production caller, while
`run_formal_strict_stage_v09` hard-fails when the authorization file is absent.

**Root cause of the escape:** every existing bridge test asserts that a guard fires *before* the
model is built — `tests/test_audit_legacy_checkpoint_bridge_v09.py` even makes `torch.load` fail
the test if reached — and `tests/test_prepare_formal_strict_stage_v09.py` injects a fake
`bridge_auditor`. The real `CudaLSTM` forward path had zero coverage.

## Global Constraints

- Work only in `G:/github/pycharm/projects/neuralhydrology/.worktrees/historical-band-experts-pilot`.
- Do not train, predict, or score. Do not create or consume any authorization during this plan.
- Do not modify the frozen protocol, sealed inputs, training targets, manifests, seals, legacy
  scoring code, or legacy model results.
- Do not read formal evaluation observations (`01/10/1989`–`30/09/1999`).
- Do not delete or overwrite the existing valid
  `R09-NEST-S100.training_resource_preflight_external_audit.json`.
- Keep the fixed stage identity: scope `R09-NEST-S100`, seed `100`, device `cuda:0`, legacy root
  `results/18_lstm_fair_531`.
- Serial execution only; keep the Git worktree clean at commit time.

---

### Task 1: Failure-first tests for the real core-model interface

**Files:**
- Create: `src/26_historical_band_experts/tests/test_legacy_bridge_core_interface_v09.py`

- [x] **Step 1:** Test that the required dynamic-input key names are derived from the bound legacy
      config, not from the protocol, and that the protocol's short names are rejected as keys by a
      real `CudaLSTM`.
- [x] **Step 2:** Test that a real `CudaLSTM` and `build_model_v09("classic_lstm_256_clean")`
      loaded from the same six active tensors return bit-identical predictions when the core is
      addressed by config names in the sealed column order.
- [x] **Step 3:** Test that the name deriver rejects multi-frequency configs, nested feature
      groups, duplicate names, and a count that disagrees with `protocol["dynamic_input_count"]`.
- [x] **Step 4:** Run the new tests and confirm they fail against the current implementation.
      Observed: 7 failed (missing deriver), 1 passed — the passing one reproduces the production
      `KeyError: 'PRCP(mm/day)'`, so it is a characterization test for the defect.

### Task 2: Fix the bridge and record the mapping as evidence

**Files:**
- Modify: `src/26_historical_band_experts/audit_legacy_checkpoint_bridge_v09.py`
- Modify: `src/26_historical_band_experts/run_formal_strict_stage_v09.py`

- [x] **Step 1:** Add `_legacy_dynamic_input_names_v09(config, expected_count)` and key
      `core_data["x_d"]` by its result, positionally aligned with the sealed forcing column order.
- [x] **Step 2:** Require all eight registered runs to yield identical names; record them in the
      report as `legacy_dynamic_input_names`.
- [x] **Step 3:** ~~structurally validate~~ **Upgraded during implementation to exact value
      binding.** The plan assumed exact validation was impossible. That was wrong:
      `formal_input_contract_v09.DYNAMIC_COLUMNS_V09` is the frozen tuple the sealed
      `forcing.npy` columns were built from, and it is byte-identical to the legacy configs'
      `dynamic_inputs` — `("PRCP(mm/day)", "Tmin(C)", "Tmax(C)", "SRAD(W/m2)", "Vp(Pa)")`. The
      bridge now rejects any legacy config that leaves that contract, and
      `_validate_legacy_bridge_report_v09` binds the reported names by value. This makes the
      positional `x_d` assignment verified rather than assumed.
- [x] **Step 4:** Rerun Task 1 tests; they must now pass. Observed: 10 passed.

### Task 3: Add the two missing closed production entries

**Files:**
- Create: `src/26_historical_band_experts/create_formal_strict_authorization_v09.py`
- Create: `src/26_historical_band_experts/audit_formal_strict_stage_v09.py`
- Create: `src/26_historical_band_experts/tests/test_formal_strict_stage_entries_v09.py`
- Modify: `src/26_historical_band_experts/run_formal_strict_stage_v09.py` (`_EXECUTABLE_FILES`)

- [x] **Step 1:** Write failure-first tests: both entries take no arguments; the authorization
      entry refuses when either prerequisite report is missing, when the worktree is dirty, when an
      authorization/consumption/output already exists, and never overwrites; the audit entry refuses
      when the consumption receipt, run directory, or seal is absent, and refuses to write its
      report inside the sealed run. **Process deviation:** these tests were written before the two
      modules existed (so they could only have failed on import), but unlike Task 1 they were not
      executed in a separate red run before implementation.
- [x] **Step 2:** Implement the authorization entry: revalidate both prerequisite reports, recompute
      the executable tree, bind the full HEAD, build the receipt with the exact frozen approval
      text, write it exclusively, then re-read and re-validate from disk.
- [x] **Step 3:** Implement the audit entry: require the consumption receipt and sealed run, check
      live host and device-0 resources under the global serial lease using the conservative training
      estimate, then run `audit_strict_run_v09` to a report path outside the sealed run.
- [x] **Step 4:** Add `create_formal_strict_authorization_v09.py` to `_EXECUTABLE_FILES` so the
      receipt binds the code that minted it. The audit entry is deliberately left out: it runs
      after training and must not be part of the pre-training trust chain.

### Task 4: Verify, review, commit

- [x] **Step 1:** Run the full `src/26_historical_band_experts/tests` suite serially.
      Observed: **610 passed, 2 failed**. Both failures are pre-existing and unrelated:
      `test_build_formal_inputs_v09.py` asserts that the formal input entry fails for lack of an
      authorization, but the entry now fails earlier because the real consumption receipt
      `formal_input_seal_authorization_consumed.json` exists (written 2026-08-01 11:15, three days
      before this work). `build_formal_inputs_v09.py` imports none of the changed modules. These two
      tests are coupled to production state and will fail for anyone running the suite after input
      sealing; fixing them is out of this plan's approved scope.
- [x] **Step 2:** Run `python -m compileall` on changed modules and `git diff --check`. Both clean;
      no line exceeds the 120-character limit.
- [x] **Step 3:** Independent read-only review. Findings are recorded under Outcome below.
- [x] **Step 4:** Fix substantiated findings, rerun affected tests (79 passed), commit.

## Outcome and review findings

1. **The stated root cause was partly wrong and is corrected here.** This plan opened by claiming
   the real `CudaLSTM` forward path had zero coverage. It does not.
   `tests/test_core_classic_equivalence_v09.py` exercises it thoroughly and asserts bit-exact
   agreement of predictions, loss, gradients, gradient norm, Adam state, and updated parameters —
   and it builds `core_data["x_d"]` from `config.dynamic_inputs`, which is the *correct* pattern.
   The accurate finding is sharper: the repository contained the right pattern in a test and the
   wrong pattern in production, and the production function `audit_legacy_checkpoint_bridge_v09`
   was never executed against a real model by any test, so the two never met.
2. **The positional mapping is verified, not assumed.** `DYNAMIC_COLUMNS_V09` (the tuple the sealed
   `forcing.npy` columns were built from) is byte-identical to the eight legacy configs'
   `dynamic_inputs`. Both the bridge and the launch validator now enforce that equality.
3. The bridge is additionally self-protecting: `classic`/`nested` consume `recent` positionally
   while the core consumes the named dict, and any disagreement must be exactly `0.0`. A wrong
   mapping raises rather than silently producing plausible numbers.
4. Import ordering in `run_formal_strict_stage_v09.py` was corrected after review.

**Not fixed (out of scope, flagged):** the two `test_build_formal_inputs_v09.py` failures above are
a test-design defect — they assume production state that now exists permanently.

## Stopping Conditions

Stop without changing formal evidence if: any frozen hash drifts; the worktree is dirty at commit
time; a path link or junction is found; the existing resource preflight report would be modified;
any new code path can train, predict, score, or read formal evaluation observations; or the bridge
still cannot produce bit-identical predictions against the frozen checkpoints.

## Explicitly Out of Scope

Running the prepared stage. After this plan is committed, the strict-nesting training stage must be
requested again and re-approved separately.
