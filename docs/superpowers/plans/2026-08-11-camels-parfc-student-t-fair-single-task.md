# CAMELS Maximum Soil-Water Capacity Student-t Fair Single-Task Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Compare full state interaction and nine-path observation-postcollapse using the same online Student-t model evidence for basin `07184000`, design seed `0`, without changing their internal Gaussian state updates.

**Architecture:** Add one validated multivariate Student-t log-evidence function and one optional `FilterStepResult -> float` model-evidence scorer to both multiple-model estimators. Keep the default scorer equal to the existing Gaussian filter likelihood so all legacy calls remain bitwise unchanged. Run the two estimators from identical registered inputs into one new isolated diagnostic output root.

**Tech Stack:** Python 3.11, NumPy 1.26, pytest, Matplotlib.

## Global Constraints

- Write only under `G:\wt\camels-rising`; keep the main repository read-only.
- Preserve the dirty worktree and all frozen evidence; do not commit, push, delete, overwrite, or clean.
- Use only basin `07184000` and design seed `0` in this diagnostic.
- Do not create or freeze a new formal version-03B configuration or launch the 20-task or 90-basin design.
- Change one scientific factor only: Gaussian versus Student-t model evidence. Keep truth, observations, forcing, candidate parameters, process covariance, observation covariance, state mapping, state-update equations, transition matrix, and initial moments fixed.
- Report parameter-candidate identification only; do not infer state accuracy, forecast value, noise identification, or real-observation assimilation value.

---

### Task 1: Student-t model-evidence primitive

**Files:**
- Modify: `test/test_hbv_joint_uncertainty_imm.py`
- Modify: `src/hbv_joint_uncertainty/imm.py`

**Interfaces:**
- Produces: `student_t_log_model_evidence(innovation, innovation_scale, degrees_of_freedom) -> float`
- Produces: `student_t_model_evidence_scorer(degrees_of_freedom) -> Callable[[FilterStepResult], float]`

- [ ] **Step 1: Write failing scalar and multivariate closed-form tests**

Test the scalar Cauchy identity
`-log(pi) - 0.5*log(S) - log1p(r*r/S)` and a two-dimensional diagonal-scale reference computed directly from `lgamma`, `slogdet`, and `solve`.

- [ ] **Step 2: Write failing validation tests**

Reject zero, negative, non-finite degrees of freedom; mismatched innovation/scale shapes; non-finite inputs; nonsymmetric or non-positive-definite scales.

- [ ] **Step 3: Run the new tests and confirm failure**

Run:
`C:\Users\yiqun\anaconda3\python.exe -m pytest -q test/test_hbv_joint_uncertainty_imm.py -k "student_t_log_model_evidence"`

Expected: collection or attribute failures because the functions do not exist.

- [ ] **Step 4: Implement the minimum validated formula and scorer factory**

Use
`lgamma((nu+d)/2) - lgamma(nu/2) - 0.5*(logdet(S)+d*log(nu*pi)) - 0.5*(nu+d)*log1p(delta2/nu)`
with `delta2 = r.T @ solve(S, r)`.

- [ ] **Step 5: Run the focused tests and confirm pass**

Run the command from Step 3; expected result: all selected tests pass.

### Task 2: Equal online evidence interface for both estimators

**Files:**
- Modify: `test/test_hbv_joint_uncertainty_imm.py`
- Modify: `src/hbv_joint_uncertainty/imm.py`
- Modify: `src/camels_switch_confirmation/g2_switch_confirmation.py`

**Interfaces:**
- Extends: `InteractingMultipleModel(..., model_evidence_scorer=None)`
- Extends: `PairwisePathMultipleModel(..., model_evidence_scorer=None)`
- Extends: `_build_bank(..., model_evidence_scorer=None)`
- Default: `None` uses each `FilterStepResult.log_likelihood` exactly as before.

- [ ] **Step 1: Write failing estimator-use tests**

For each estimator, inject a scorer that returns fixed unequal scores, verify the scorer is called once per active candidate or branch, verify posterior weights follow those scores, and verify every candidate or branch `FilterStepResult` state and covariance equal a Gaussian-default control.

- [ ] **Step 2: Write failing compatibility tests**

Run identical default and explicit-Gaussian scorers and require exact equality of ordinary probabilities, stable log probabilities, combined state, and combined covariance.

- [ ] **Step 3: Run the estimator tests and confirm failure**

Run:
`C:\Users\yiqun\anaconda3\python.exe -m pytest -q test/test_hbv_joint_uncertainty_imm.py -k "model_evidence_scorer or explicit_gaussian"`

- [ ] **Step 4: Add the optional scorer to both estimators and the bank builder**

Validate the scorer is callable, require every returned score to be a finite scalar, and use it only where candidate or branch model weights are formed. Do not change `ModifiedUnscentedFilter` or `FilterStepResult.log_likelihood`.

- [ ] **Step 5: Run focused and existing interacting-model tests**

Run:
`C:\Users\yiqun\anaconda3\python.exe -m pytest -q test/test_hbv_joint_uncertainty_imm.py test/test_camels_switch_confirmation.py`

Expected: all tests pass; legacy Gaussian tests retain their exact expected values.

### Task 3: Isolated fair single-task experiment

**Files:**
- Create by experiment execution only: `results/23_camels_switch_confirmation/camels_parfc_model_evidence_fair_07184000_s0_01_20260811_local/`
- Create by experiment execution only: `.../full_interaction_student_t/probabilities.npz`
- Create by experiment execution only: `.../nine_path_student_t/probabilities.npz`
- Create by experiment execution only: `.../summary.json`

**Interfaces:**
- Consumes: registered version-03B design-90 parameter table, raw-input manifest, and frozen `07184000_s0` truth/observation arrays after verifying their hashes.
- Produces: two complete 1260-day probability trajectories and one comparison summary.

- [ ] **Step 1: Fail fast before output creation**

Verify repository revision, registered input hashes, basin identity, seed `0`, frozen-source fingerprint, code hashes, array shapes, finite values, and that the new output root does not exist and is not inside any frozen result tree.

- [ ] **Step 2: Run full interaction with Student-t degrees of freedom 1**

Use `_build_bank(..., interaction_mode="full", parameter_state_mapping="conservative_parfc", model_evidence_scorer=student_t_model_evidence_scorer(1.0))` and the frozen forcing and observations.

- [ ] **Step 3: Run nine-path observation-postcollapse with the identical scorer**

Use the same call except `interaction_mode="pairwise_path_postcollapse"`; preserve all other values exactly.

- [ ] **Step 4: Save atomic, non-overwriting artifacts and metrics**

For each method save ordinary probabilities, stable log probabilities, true-candidate indices, truth capacity, observations, and fixed-setting metadata. In `summary.json`, report each 180-day stage, especially days 540-719 and 720-899: zero days, days below 0.01, days below 0.5, mean true probability, median true probability, final-day true probability, mean negative stable log probability, multiclass Brier score, and six event outcomes.

- [ ] **Step 5: Verify the new artifacts and frozen evidence**

Reload all new files with `allow_pickle=False`, recompute every summary metric independently, and confirm the frozen result fingerprint remains `57d8fef9037c29d0a68f915d5337f3be7bfab2224ebada575be6161e070126e6`.

### Task 4: Clear probability comparison

**Files:**
- Create: `C:\Users\yiqun\.codex\visualizations\2026\08\11\019feee1-e311-7f83-be48-b3e643cfb14c\camels_07184000_student_t_fair_comparison.png`

**Interfaces:**
- Consumes: verified new full-interaction and nine-path Student-t trajectories.
- Produces: one clear chart of the probability assigned to the true candidate.

- [ ] **Step 1: Plot only days 540-899**

Draw the true target line at 1 and the two fair Student-t trajectories; mark the day-720 parameter switch and show days 540-719 and 720-899 as separate visual regions.

- [ ] **Step 2: Put decisive metrics outside the data region**

Show final-day probability and days below 0.5 for each 180-day stage; do not call removal of numerical zeros a scientific success.

- [ ] **Step 3: Render and visually inspect the image**

Require readable Chinese text, unobscured curves, y-axis `[0,1]`, and no legend covering data.

### Task 5: Decision

**Files:**
- No additional files.

- [ ] **Step 1: Apply the scientific interpretation boundary**

Call Student-t evidence useful only if it improves the full 180-day target stage without transferring an equivalent failure to the next stage, and compare full interaction versus nine-path under identical Student-t evidence.

- [ ] **Step 2: Report fact, inference, and unknown separately**

State whether the original highlighted failure persists, whether the next stage degrades, which method is better on this one task, and that generalization beyond basin `07184000`, seed `0` remains unverified.
