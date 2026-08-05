# ID23 Interacting Multiple-Model Global Posterior Contract Correction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Execute this plan inline and review every change against the frozen-evidence boundary. Do not dispatch subagents for this task.

**Goal:** Make the unique global posterior state produced at the end of every interacting multiple-model update the unambiguous primary state estimate throughout code, documentation, experiment definitions, and memory.

**Architecture:** Preserve all sealed arrays, result directories, historical experiment identifiers, and numerical conclusions. Add canonical runtime accessors and terminology for the global posterior; retain model-conditioned subfilter states only as internal diagnostics or explicitly labeled multi-trajectory controls. Correct active documents and add immutable sidecar corrections for frozen configurations rather than rewriting archived artifacts.

**Tech Stack:** Python, NumPy, pytest, Markdown, JSON, CSV.

## Global Constraints

- The standard fully interacting multiple-model method ends every observation update with one posterior-probability-weighted global posterior state and covariance.
- Model-conditioned subfilter posterior states remain internal states; using one of them or forecasting all of them is an explicit diagnostic or ensemble control, not the method's final state output.
- A no-state-interaction comparison must still produce one probability-weighted global posterior state after each update; it is a non-interacting multi-filter control, not the standard fully interacting method.
- Do not modify sealed result arrays, result checksums, archived output directories, or historical numerical values.
- Do not claim that the completed one-filter-versus-three-filter experiment isolates candidate count or state interaction; it compares a single filter with the fully interacting three-model method as a whole.
- Do not stage, commit, delete, or clean unrelated worktree changes.

---

### Task 1: Canonical runtime state-output contract

**Files:**
- Modify: `src/hbv_joint_uncertainty/imm.py`
- Modify: `src/hbv_joint_uncertainty/preflight.py`
- Modify: `src/hbv_multilead_joint_uncertainty/methods.py`
- Modify: `src/hbv_multilead_joint_uncertainty/three_stage_switching_validation.py`
- Modify: `test/test_hbv_joint_uncertainty_imm.py`
- Modify: `test/test_hbv_joint_uncertainty_preflight.py`

**Interfaces:**
- Produces: `InteractingStepResult.global_posterior_state`, `InteractingStepResult.global_posterior_covariance`, `InteractingMultipleModel.global_posterior_state`, and `InteractingMultipleModel.global_posterior_covariance` while retaining archived `combined_state` and `combined_covariance` aliases.
- Consumes: explicit interaction modes `full`, `parameter_grouped`, and `none`.

- [x] **Step 1: Add failing tests that reconstruct the global posterior from model-conditioned posterior states and probabilities**

```python
expected = sum(
    probability * result.posterior_state
    for probability, result in zip(step.posterior_probabilities, step.candidate_results)
)
np.testing.assert_allclose(step.global_posterior_state, expected)
np.testing.assert_allclose(estimator.global_posterior_state, expected)
```

- [x] **Step 2: Run the focused tests and require the new accessors to fail before implementation**

Run: `python -m pytest test/test_hbv_joint_uncertainty_imm.py test/test_hbv_joint_uncertainty_preflight.py -q`

Expected: failure because the canonical global-posterior accessors do not yet exist.

- [x] **Step 3: Add canonical accessors and explicit interaction-mode construction without changing numerical calculations**

Use the existing posterior-probability mixture for the global posterior. Preserve old field names only as compatibility names for frozen artifacts.

- [x] **Step 4: Replace active assimilation reads of the ambiguous estimator state with the canonical global-posterior accessor**

The saved arrays remain numerically identical and retain their archived keys.

- [x] **Step 5: Run the focused tests and require them to pass**

Run: `python -m pytest test/test_hbv_joint_uncertainty_imm.py test/test_hbv_joint_uncertainty_preflight.py test/test_hbv_multilead_methods.py -q`

Expected: all pass with unchanged numerical values.

### Task 2: Remove misleading forecast-readout API names

**Files:**
- Modify: `src/hbv_multilead_joint_uncertainty/forecast_readout.py`
- Modify: `src/hbv_multilead_joint_uncertainty/scripts/run_g3_daily_rolling_forecast_readout_development.py`
- Modify: `test/test_hbv_forecast_readout.py`

**Interfaces:**
- Produces: `ForecastReadoutResult.global_posterior_state`, `historical_covariance_prediction`, and `ensemble_control_prediction`.
- Removes from active use: `PRIMARY_SINGLE_STATE_READOUT`, `primary_prediction`, and `posterior_mean_state` as primary-method labels.

- [x] **Step 1: Add tests that require the canonical global posterior and reject a primary label for the archived covariance propagation**

```python
np.testing.assert_allclose(result.global_posterior_state, posterior.mean_state)
assert not hasattr(result, "primary_prediction")
```

- [x] **Step 2: Run the forecast-readout test and confirm it fails under the old API**

Run: `python -m pytest test/test_hbv_forecast_readout.py -q`

- [x] **Step 3: Rename active accessors while preserving frozen result keys in archived writers**

The string `current_multiple_states` remains only as an explicitly documented historical artifact key for a model-conditioned multi-trajectory ensemble control.

- [x] **Step 4: Run forecast-readout and runner tests**

Run: `python -m pytest test/test_hbv_forecast_readout.py test/test_hbv_daily_rolling_forecast_readout_runner.py test/test_hbv_daily_rolling_forecast_readout_verifier.py -q`

Expected: all pass without changing archived numerical arrays.

### Task 3: Correct completed experiment semantics without rewriting frozen evidence

**Files:**
- Modify: `src/hbv_multilead_joint_uncertainty/fixed_process_parameter_candidate_state_audit.py`
- Modify: `src/hbv_multilead_joint_uncertainty/fixed_process_parameter_candidate_forecast.py`
- Modify: `src/hbv_multilead_joint_uncertainty/scripts/run_g3_fixed_process_parameter_candidate_complete_state_audit.py`
- Create: `src/hbv_multilead_joint_uncertainty/configs/g3_fixed_process_parameter_candidate_complete_state_audit_v01.scope_correction_20260801.json`
- Create: `src/hbv_multilead_joint_uncertainty/configs/g3_fixed_process_parameter_candidate_controlled_forecast_v01.scope_correction_20260801.json`
- Modify: `src/hbv_multilead_joint_uncertainty/configs/g3_experiment_registry.csv`
- Modify: relevant state-audit tests and verifiers.

**Interfaces:**
- Produces: an explicit mapping from archived keys to `single_filter_posterior_state` and `fully_interacting_multiple_model_global_posterior_state`.
- States: the completed comparison is an overall method comparison, not an isolated candidate-count or interaction-effect experiment.

- [x] **Step 1: Add tests for the immutable sidecar correction and canonical method-role mapping**

Require `historical_config_immutable=true`, `standard_method_output=fully_interacting_multiple_model_global_posterior_state`, and `mechanism_attribution_allowed=false`.

- [x] **Step 2: Rename active Python symbols from method names to archived artifact keys and add canonical role metadata**

Do not change the two legacy string keys stored in the completed result package.

- [x] **Step 3: Add sidecar corrections and update registry wording**

The registry must identify the full-interaction method and explicitly forbid candidate-count-only or interaction-only attribution.

- [x] **Step 4: Run the complete-state and controlled-forecast test suites**

Run: `python -m pytest test/test_hbv_fixed_process_parameter_candidate_state_audit.py test/test_hbv_fixed_process_parameter_candidate_state_audit_runner.py test/test_hbv_fixed_process_parameter_candidate_state_audit_verifier.py test/test_hbv_fixed_process_parameter_candidate_forecast.py test/test_hbv_fixed_process_parameter_candidate_forecast_runner.py test/test_hbv_fixed_process_parameter_candidate_forecast_verifier.py -q`

Expected: all pass and the existing evidence hashes remain unchanged.

### Task 4: Correct active documentation and future experiment design

**Files:**
- Modify: `src/hbv_multilead_joint_uncertainty/HANDOFF_20260731_SINGLE_STATE_CONTRACT_CORRECTION.md`
- Modify: `src/hbv_multilead_joint_uncertainty/HANDOFF_20260801_COMPLETE_STATE_PARAMETER_CONTROL.md`
- Modify: `src/hbv_multilead_joint_uncertainty/HANDOFF_20260801_FIXED_PROCESS_PARAMETER_CANDIDATE_CONTROL.md`
- Modify: active ID23 design and closure documents dated 2026-07-28 through 2026-08-01.
- Modify: `G:/github/pycharm/projects/neuralhydrology/src/hbv_multilead_joint_uncertainty/HANDOFF_20260728_DAILY_ROLLING_FORECAST_CORRECTION.md`
- Modify: `G:/github/pycharm/projects/paper-imm-variable-params/docs/forecast_readout_contract_20260731.md`
- Modify: `G:/github/pycharm/projects/paper-imm-variable-params/AGENTS.md`
- Create: `docs/plans/2026-08-01-id23-state-interaction-global-posterior-audit-design.md`
- Create: `src/hbv_multilead_joint_uncertainty/configs/g3_fixed_process_state_interaction_global_posterior_audit_v01.json`
- Modify: `src/hbv_multilead_joint_uncertainty/configs/g3_experiment_registry.csv`

**Interfaces:**
- Produces: one canonical explanation of standard fully interacting updating, one non-interacting control definition, and one planned same-day global-posterior state audit with no forecast.

- [x] **Step 1: Replace language that treats posterior state combination as an optional post-processing forecast form**

Use: “the standard fully interacting method already produces one global posterior state at the end of the update.”

- [x] **Step 2: Label model-conditioned subfilter states consistently**

They may be inspected, selected, or propagated only as diagnostics or ensemble controls and may not be called the final method output.

- [x] **Step 3: Freeze the interaction-only state-audit design**

Compare the same three fixed parameter models under `full` versus `none`; keep observations, process covariance, transition-probability prediction, probability update, initial conditions, truth, and all 540 days fixed; compare only each method's daily global posterior with same-day fifteen-state truth; execute no forecast.

- [x] **Step 4: Search active files for forbidden ambiguity**

Run: `rg -n "压缩为唯一状态|PRIMARY_SINGLE_STATE_READOUT|only_changed_factor.*candidate count|当前多个状态方法" src/hbv_multilead_joint_uncertainty docs/plans docs/superpowers/plans test`

Expected: no active unqualified use; any retained historical phrase must be immediately labeled as an archived artifact or ensemble control.

### Task 5: Independent verification and authorized memory correction

**Files:**
- Create: `docs/plans/2026-08-01-id23-imm-global-posterior-contract-correction-closure.md`
- Create: `C:/Users/yiqun/.codex/memories/extensions/ad_hoc/notes/<timestamp>-id23-imm-global-posterior-contract-correction.md`

**Interfaces:**
- Produces: a file-by-file audit status, unchanged-evidence hashes, test results, and a memory note that supersedes ambiguous earlier wording.

- [x] **Step 1: Hash the completed state and forecast evidence before and after edits**

Require the state evidence SHA-256 to remain `0826bf9b27fd4d42c2a5874835e509f4d84f73af7ffb9ee30f98dd3a8375766d` and record the controlled-forecast evidence hash from disk without altering it.

- [x] **Step 2: Run all targeted regression tests and a source/config terminology audit**

Run the test groups from Tasks 1 through 3 plus JSON parsing for all new sidecars and the planned config.

- [x] **Step 3: Write the correction closure with facts, limitations, and next experiment status**

State separately what was corrected, what sealed evidence remains unchanged, and what scientific question remains unanswered.

- [x] **Step 4: Add one authorized memory update note**

The note must say that the standard method's final state is the unique global posterior, model-conditioned states are internal, the completed one-versus-three comparison is an overall method comparison, and the clean interaction-only same-day state experiment remains planned.
