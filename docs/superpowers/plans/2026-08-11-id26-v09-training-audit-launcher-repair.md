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

- [x] **Step 1: Fast-forward the isolated audit checkout to the exact new commit and verify it is clean**
- [x] **Step 2: Require job 202586 to remain `FAILED,1:0` and require the audit report to remain absent**
- [x] **Step 3: Submit `audit_formal_training_v09.slurm` once and write `training_audit_attempt_02_jobid.txt`**
- [x] **Step 4: Return immediately with the new job identifier and queue state; do not wait on the login node**
- [x] **Step 5: Resume the two-hour monitor with the new commit, job identifier, pass gates, and no automatic cleanup**

### Task 3: Preserve non-ASCII tracked Git paths in the production source seal

**Files:**
- Modify: `src/26_historical_band_experts/audit_formal_training_v09.py`
- Modify: `src/26_historical_band_experts/tests/test_audit_formal_training_v09.py`

**Interfaces:**
- Consumes: a Git worktree whose tracked paths may contain non-ASCII characters or newlines.
- Produces: `_tracked_git_files(repo_root: Path) -> tuple[str, ...]`, using UTF-8-decoded, NUL-delimited
  `git ls-files -z` output without display quoting.

- [x] **Step 1: Add a regression test with a tracked Chinese path**

```python
def test_tracked_git_files_preserves_non_ascii_path(tmp_path):
    from audit_formal_training_v09 import _tracked_git_files

    repo = tmp_path / "repo"
    subprocess.run(["git", "init", "-q", str(repo)], check=True)
    relative = Path(".cursor/plans/全球水文模型论文计划_ee017201.plan.md")
    path = repo / relative
    path.parent.mkdir(parents=True)
    path.write_text("plan\n", encoding="utf-8")
    subprocess.run(["git", "-C", str(repo), "add", "--", relative.as_posix()], check=True)
    assert _tracked_git_files(repo) == (relative.as_posix(),)
```

- [x] **Step 2: Run the focused test and verify it fails because the helper is absent**

Run: `pytest src/26_historical_band_experts/tests/test_audit_formal_training_v09.py::test_tracked_git_files_preserves_non_ascii_path -q`

Expected: FAIL with an import error for `_tracked_git_files`.

- [x] **Step 3: Implement NUL-delimited tracked-path parsing and use it in the production source seal**

```python
def _tracked_git_files(repo_root: Path) -> tuple[str, ...]:
    return tuple(value for value in _run_git(repo_root, "ls-files", "-z").split("\0") if value)
```

Configure `_run_git` with `encoding="utf-8"` and `errors="surrogateescape"`, then replace the line-oriented
`git ls-files` parsing in `_production_source_seal` with `_tracked_git_files(repo_root)`.

- [x] **Step 4: Run the focused test and the complete training-audit test file**

Run: `pytest src/26_historical_band_experts/tests/test_audit_formal_training_v09.py -q`

Expected: PASS.

- [x] **Step 5: Commit the plan, regression test, and one-factor source fix**

Commit message: `Fix: Preserve non-ASCII Git paths in training audit`.

### Task 4: Submit training-audit attempt 03 from the verified source fix

**Files:**
- Modify remotely through the Git mailbox only: `inbox/id26-v09-strict/cmd.sh`, `inbox/id26-v09-strict/seq`
- Preserve: `/data1/home/sunyiq/v09_strict/audit_v09/training_audit_attempt_02_jobid.txt`
- Create remotely: `/data1/home/sunyiq/v09_strict/audit_v09/training_audit_attempt_03_jobid.txt`

**Interfaces:**
- Consumes: the exact Task-3 commit, its parent `ac258afd31d835d93137da8961dc1206a1ee844c`, and an embedded full-index Git patch.
- Produces: a hash-verified audit checkout and one Slurm submission for attempt 03.

- [ ] **Step 1: Generate the exact full-index patch and commit metadata**

Run: `git diff -U0 --full-index --binary ac258afd31d835d93137da8961dc1206a1ee844c HEAD -- docs/superpowers/plans/2026-08-11-id26-v09-training-audit-launcher-repair.md src/26_historical_band_experts/audit_formal_training_v09.py src/26_historical_band_experts/tests/test_audit_formal_training_v09.py`

- [ ] **Step 2: Embed the patch in the next single mailbox command**

Use a new alternate index, `git read-tree`, `git apply --cached --unidiff-zero`, `git write-tree`, and `git commit-tree`; require both the reconstructed tree and commit to equal the local Task-3 commit before checkout.

- [ ] **Step 3: Preserve attempts 01 and 02 and require the audit report to remain absent**

Require job 202586 to remain `FAILED,1:0`, job 202755 to remain `FAILED,1:0`, and `training_external_audit.json` not to exist.

- [ ] **Step 4: Submit the audit once and write `training_audit_attempt_03_jobid.txt`**

Run remotely: `sbatch --parsable src/26_historical_band_experts/hpc/audit_formal_training_v09.slurm` from the exact reconstructed audit checkout.

- [ ] **Step 5: Return immediately and resume two-hour monitoring of only the new job**

## Self-Review

- Spec coverage: the plan repairs only the observed launcher and Git-path parsing failures and preserves all scientific and evidence constraints.
- Placeholder scan: no deferred implementation placeholders remain.
- Type consistency: no Python interfaces or report schemas change.
- Execution choice: the user already instructed Codex to solve recoverable problems autonomously, so execution continues inline in this session.
