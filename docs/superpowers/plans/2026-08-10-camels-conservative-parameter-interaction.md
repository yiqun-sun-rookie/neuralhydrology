# CAMELS Conservative Parameter Interaction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:writing-plans to execute this plan task by task.

**Goal:** Add a physically conservative state conversion for soil-capacity changes and use it in a full, target-conditioned interacting multiple-model update without changing the legacy parameter-grouped experiment path.

**Architecture:** Keep the hydrologic state conversion in a new pure module. Extend the generic interacting multiple-model implementation with an optional source-to-destination moment-transform callback; the default remains byte-for-byte compatible. Expose the corrected behavior in the CAMELS parameter-switch runner only through explicit options, so old configurations and frozen evidence continue to use their original behavior.

**Tech Stack:** Python, NumPy, pytest, existing HBV-lite adapter, existing scaled-sigma-point filter.

**Safety boundary:** Do not edit the main repository, remove or overwrite existing results, create a frozen configuration, use seeds 2 or 3, run all 531 basins, commit, or push.

---

### Task 1: Test and implement conservative soil-capacity state conversion

**Files:**
- Create: `src/hbv_joint_uncertainty/hbv_state_mapping.py`
- Create: `test/test_hbv_parameter_state_mapping.py`

1. Add failing tests for exact identity, capacity increase, non-binding reduction, capacity reduction with excess soil water transferred to the upper groundwater store, preservation of all routing-memory states, and rejection of parameter pairs that differ in anything other than soil capacity.
2. Add moment-level tests using the existing scaled sigma points. In an affine reduction case, compare against the analytical `J P J^T`; across the capacity kink, verify preservation of the mean and variance of soil water plus upper groundwater, finite symmetric covariance, and non-negative eigenvalues within numerical tolerance.
3. Implement `remap_parfc_state(state, source_parameters, destination_parameters)` as a pure function. If soil water exceeds the destination capacity, set it to the destination capacity and add the exact excess to the upper groundwater store. Otherwise return an exact copy.
4. Implement `remap_parfc_moments(mean, covariance, source_parameters, destination_parameters, sigma_points)` by transforming every sigma point before reconstructing the moments. Same-capacity conversion must return exact copies without numerical transformation.
5. Add hard validation for finite values, fifteen-state shape, positive capacity, conservation, covariance symmetry, and covariance positive semidefiniteness. Do not repair invalid outputs by clipping.

### Task 2: Test and implement target-conditioned moment conversion in the interacting multiple-model method

**Files:**
- Modify: `src/hbv_joint_uncertainty/imm.py`
- Modify: `test/test_hbv_joint_uncertainty_imm.py`

1. Add a failing hand-calculated test with source `(soil water, upper groundwater)` states `(80, 10)` and `(160, 20)`, destination capacities `100` and `200`, probabilities `(0.75, 0.25)`, and transition matrix `[[0.8, 0.2], [0.3, 0.7]]`. For destination capacity `100`, require conditional source weights `(8/9, 1/9)` and mixed state `(82.222222..., 17.777777...)`.
2. Extend `interact_model_states` with optional `pairwise_moment_transform(source_index, destination_index, mean, covariance)`. For each destination, transform every permitted source moment first, then apply the existing conditional mixture equations.
3. Extend `InteractingMultipleModel` with the same optional callback and pass it through `_interact`. Do not invoke it in no-interaction mode.
4. Prove by regression tests that omitting the callback, supplying an identity callback, and retaining parameter-grouped mode reproduce the legacy numerical results. Keep the existing cross-parameter-no-mixing test unchanged.

### Task 3: Add an explicit corrected mode to the CAMELS parameter-switch runner

**Files:**
- Modify: `src/camels_switch_confirmation/g2_switch_confirmation.py`
- Modify: `test/test_camels_switch_confirmation.py`

1. Add explicit runner options for state interaction and capacity-state conversion. Defaults must remain `parameter_grouped` and legacy direct projection so old configurations do not silently change.
2. In corrected mode, initialize each candidate by conservatively mapping the shared calibrated state from the center-parameter space into that candidate's space.
3. Build a source-to-destination moment callback from the candidate parameter dictionaries and each source filter's existing sigma-point generator. Require full interaction when conservative cross-parameter conversion is selected.
4. Record both choices in result metadata and expose command-line flags for an isolated development smoke run. Old configurations missing the fields must retain legacy defaults.
5. Add tests that the corrected bank uses full interaction and conservative conversion, that initialization preserves water, that a truth boundary step agrees with an explicit conservative conversion followed by the new-parameter model step, and that legacy defaults remain unchanged.

### Task 4: Verify without consuming validation evidence

**Files:**
- Test: `test/test_hbv_parameter_state_mapping.py`
- Test: `test/test_hbv_joint_uncertainty_imm.py`
- Test: `test/test_camels_switch_confirmation.py`

1. Run the new mapping tests alone and fix only implementation defects exposed by them.
2. Run the interacting multiple-model and CAMELS task-specific test files.
3. Run the existing preflight tests far enough to confirm no new failure occurs before the known missing external fixture; report that fixture failure separately if it remains.
4. If all task tests pass, run one seed-0 basin into a new, non-existing output directory as a smoke test. Verify finite normalized probabilities, exact task completion, recorded corrected-mode metadata, and no overwrite.
5. Stop after the smoke evidence. Do not freeze a configuration or draw a candidate-identification conclusion from one basin.
