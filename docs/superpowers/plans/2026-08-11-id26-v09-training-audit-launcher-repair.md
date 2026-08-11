# ID26 Version-09 Training Audit Launcher Repair Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Repair the three authorized audit and diagnostics Slurm launchers so they start in the existing `nh_final` environment without weakening strict shell checks after activation.

**Architecture:** Preserve failed job 202586 and every frozen training artifact. Change only the common launcher boundary in the training audit, state diagnostics, and independent state replay: explicitly disable Bash nounset while Conda activation scripts run, then re-enable nounset before any audit paths, checks, or Python code execute. Submit a new training-audit attempt from a new audit-code commit and record a new Slurm job identifier.

**Tech Stack:** Bash, Slurm, Conda, pytest, Git mailbox.

## Global Constraints

- Do not modify the frozen training checkout at `bb519b8b9980725ac1d5f4e298d76ae80ea2c58d` or the frozen strict-evidence checkout.
- Do not modify, delete, or overwrite sealed training outputs or failed-job logs.
- Do not generate formal predictions, read formal-evaluation observations, or call official scoring.
- Treat the new submission as audit attempt 02; job 202586 remains the immutable attempt-01 failure record.
- Keep the missing canonical four-workload resource-preflight report as a final HOLD blocker.

---

### Task 1: Scope Bash nounset around Conda activation

**Files:**
- Modify: `src/26_historical_band_experts/hpc/audit_formal_training_v09.slurm`
- Modify: `src/26_historical_band_experts/hpc/state_diagnostics_formal_v09.slurm`
- Modify: `src/26_historical_band_experts/hpc/audit_state_diagnostics_formal_v09.slurm`
- Modify: `src/26_historical_band_experts/tests/test_audit_formal_training_v09.py`

**Interfaces:**
- Consumes: the existing `nh_final` Conda environment and unchanged audit command.
- Produces: three authorized launchers that have nounset disabled only through `conda activate nh_final` and enabled before audit setup.

- [x] **Step 1: Write the failing regression test**

```python
@pytest.mark.parametrize("filename", [
    "audit_formal_training_v09.slurm",
    "state_diagnostics_formal_v09.slurm",
    "audit_state_diagnostics_formal_v09.slurm",
])
def test_v09_audit_slurm_scopes_nounset_around_conda_activation(filename):
    script = (IDEA_ROOT / "hpc" / filename).read_text(encoding="utf-8")
    disable_index = script.index("set +u")
    activate_index = script.index("conda activate nh_final")
    enable_index = script.index("set -u", activate_index)
    audit_setup_index = script.index("AUDIT_REPO=")
    assert disable_index < activate_index < enable_index < audit_setup_index
```

- [x] **Step 2: Run the test and verify the current launcher fails**

Run: `pytest src/26_historical_band_experts/tests/test_audit_formal_training_v09.py::test_v09_audit_slurm_scopes_nounset_around_conda_activation -q`

Expected: FAIL for the state-diagnostics and replay launchers because they do not contain `set +u`.

- [x] **Step 3: Apply the minimal launcher repair**

```bash
set -eo pipefail
set +u
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
```

- [x] **Step 4: Run the regression test and the complete training-audit test file**

Run: `pytest src/26_historical_band_experts/tests/test_audit_formal_training_v09.py -q`

Expected: PASS.

- [x] **Step 5: Validate the shell file and commit only the launcher, test, and this plan**

Run: `bash -n` separately for the three modified Slurm files.

Commit message: `Fix: Scope nounset around audit environment activation`.

### Task 2: Submit and register audit attempt 02

**Files:**
- Modify remotely through the Git mailbox only: `inbox/id26-v09-strict/cmd.sh`, `inbox/id26-v09-strict/seq`
- Preserve: `/data1/home/sunyiq/v09_strict/logs/training_audit_202586.err`

**Interfaces:**
- Consumes: the new pushed audit-code commit and the absent `training_external_audit.json` precondition.
- Produces: a new immutable job-id file for attempt 02 and one Slurm submission.

- [ ] **Step 1: Fast-forward the isolated audit checkout to the exact new commit and verify it is clean**
- [ ] **Step 2: Require job 202586 to remain `FAILED,1:0` and require the audit report to remain absent**
- [ ] **Step 3: Submit `audit_formal_training_v09.slurm` once and write `training_audit_attempt_02_jobid.txt`**
- [ ] **Step 4: Return immediately with the new job identifier and queue state; do not wait on the login node**
- [ ] **Step 5: Resume the two-hour monitor with the new commit, job identifier, pass gates, and no automatic cleanup**

## Self-Review

- Spec coverage: the plan repairs only the observed launcher failure and preserves all scientific and evidence constraints.
- Placeholder scan: no deferred implementation placeholders remain.
- Type consistency: no Python interfaces or report schemas change.
- Execution choice: the user already instructed Codex to solve recoverable problems autonomously, so execution continues inline in this session.
