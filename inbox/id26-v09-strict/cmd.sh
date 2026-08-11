#!/bin/bash
# id26-v09-strict seq=59 : reconstruct the exact audit commit from an embedded Git patch and submit attempt 02 once.
set -euo pipefail
export LC_ALL=C
ROOT=/data1/home/sunyiq/v09_strict
AUDIT_PARENT=$ROOT/audit_v09
AUDIT_REPO=$AUDIT_PARENT/neuralhydrology
TRAIN_REPO=$ROOT/codetest/neuralhydrology
STRICT_REPO=$ROOT/neuralhydrology
FORMAL_ROOT=$TRAIN_REPO/results/26_historical_band_experts/formal_v09
OLD_JOBID_FILE=$AUDIT_PARENT/training_audit_jobid.txt
NEW_JOBID_FILE=$AUDIT_PARENT/training_audit_attempt_02_jobid.txt
REPORT=$FORMAL_ROOT/training_external_audit.json
PARENT=31ff9ebe3814e088fd623b836f4a802ddab856cd
COMMIT=ac258afd31d835d93137da8961dc1206a1ee844c
EXPECTED_TREE=c90651619d44deb943c4dc1de2362cc82556c177
INDEX_FILE=$AUDIT_PARENT/transport_seq59.index
export PATH=$ROOT/gitenv/bin:$PATH

echo "=== A PRESERVED EVIDENCE ==="
OLD_JID=$(tr -d '[:space:]' < "$OLD_JOBID_FILE")
test "$OLD_JID" = 202586
IFS='|' read -r OLD_STATE OLD_EXIT <<< "$(sacct -n -X -j "$OLD_JID" --starttime 2026-08-11 --format=State,ExitCode -P)"
echo "attempt_01_jobid=$OLD_JID state=$OLD_STATE exit_code=$OLD_EXIT"
test "$OLD_STATE" = FAILED
test "$OLD_EXIT" = 1:0
test ! -e "$NEW_JOBID_FILE"
test ! -e "$REPORT"
test ! -e "$FORMAL_ROOT/state_diagnostics"
test ! -e "$FORMAL_ROOT/training_seal.json"

echo "=== B FROZEN CHECKOUTS ==="
echo "training_head=$(git -C "$TRAIN_REPO" rev-parse HEAD)"
echo "strict_head=$(git -C "$STRICT_REPO" rev-parse HEAD)"
test "$(git -C "$TRAIN_REPO" rev-parse HEAD)" = bb519b8b9980725ac1d5f4e298d76ae80ea2c58d
test "$(git -C "$STRICT_REPO" rev-parse HEAD)" = f94183209bf44ed6e672e1c23f98020905804e6d

echo "=== C EXACT OFFLINE COMMIT RECONSTRUCTION ==="
test "$(git -C "$AUDIT_REPO" rev-parse HEAD)" = "$PARENT"
test -z "$(git -C "$AUDIT_REPO" status --porcelain --untracked-files=all)"
git -C "$AUDIT_REPO" cat-file -e "$PARENT^{commit}"
if git -C "$AUDIT_REPO" cat-file -e "$COMMIT^{commit}" 2>/dev/null; then
  echo "audit_commit_object=already_present"
else
  echo "audit_commit_object=reconstruct_from_embedded_patch"
  test ! -e "$INDEX_FILE"
  GIT_INDEX_FILE="$INDEX_FILE" git -C "$AUDIT_REPO" read-tree "$PARENT"
  GIT_INDEX_FILE="$INDEX_FILE" git -C "$AUDIT_REPO" apply --cached --unidiff-zero --whitespace=nowarn - <<'ID26_PATCH_59'
diff --git a/docs/superpowers/plans/2026-08-11-id26-v09-training-audit-launcher-repair.md b/docs/superpowers/plans/2026-08-11-id26-v09-training-audit-launcher-repair.md
new file mode 100644
index 0000000000000000000000000000000000000000..8e92501d7ea39cc03772c771177d106f07dada14
--- /dev/null
+++ b/docs/superpowers/plans/2026-08-11-id26-v09-training-audit-launcher-repair.md
@@ -0,0 +1,99 @@
+# ID26 Version-09 Training Audit Launcher Repair Implementation Plan
+
+> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
+
+**Goal:** Repair the three authorized audit and diagnostics Slurm launchers so they start in the existing `nh_final` environment without weakening strict shell checks after activation.
+
+**Architecture:** Preserve failed job 202586 and every frozen training artifact. Change only the common launcher boundary in the training audit, state diagnostics, and independent state replay: explicitly disable Bash nounset while Conda activation scripts run, then re-enable nounset before any audit paths, checks, or Python code execute. Submit a new training-audit attempt from a new audit-code commit and record a new Slurm job identifier.
+
+**Tech Stack:** Bash, Slurm, Conda, pytest, Git mailbox.
+
+## Global Constraints
+
+- Do not modify the frozen training checkout at `bb519b8b9980725ac1d5f4e298d76ae80ea2c58d` or the frozen strict-evidence checkout.
+- Do not modify, delete, or overwrite sealed training outputs or failed-job logs.
+- Do not generate formal predictions, read formal-evaluation observations, or call official scoring.
+- Treat the new submission as audit attempt 02; job 202586 remains the immutable attempt-01 failure record.
+- Keep the missing canonical four-workload resource-preflight report as a final HOLD blocker.
+
+---
+
+### Task 1: Scope Bash nounset around Conda activation
+
+**Files:**
+- Modify: `src/26_historical_band_experts/hpc/audit_formal_training_v09.slurm`
+- Modify: `src/26_historical_band_experts/hpc/state_diagnostics_formal_v09.slurm`
+- Modify: `src/26_historical_band_experts/hpc/audit_state_diagnostics_formal_v09.slurm`
+- Modify: `src/26_historical_band_experts/tests/test_audit_formal_training_v09.py`
+
+**Interfaces:**
+- Consumes: the existing `nh_final` Conda environment and unchanged audit command.
+- Produces: three authorized launchers that have nounset disabled only through `conda activate nh_final` and enabled before audit setup.
+
+- [x] **Step 1: Write the failing regression test**
+
+```python
+@pytest.mark.parametrize("filename", [
+    "audit_formal_training_v09.slurm",
+    "state_diagnostics_formal_v09.slurm",
+    "audit_state_diagnostics_formal_v09.slurm",
+])
+def test_v09_audit_slurm_scopes_nounset_around_conda_activation(filename):
+    script = (IDEA_ROOT / "hpc" / filename).read_text(encoding="utf-8")
+    disable_index = script.index("set +u")
+    activate_index = script.index("conda activate nh_final")
+    enable_index = script.index("set -u", activate_index)
+    audit_setup_index = script.index("AUDIT_REPO=")
+    assert disable_index < activate_index < enable_index < audit_setup_index
+```
+
+- [x] **Step 2: Run the test and verify the current launcher fails**
+
+Run: `pytest src/26_historical_band_experts/tests/test_audit_formal_training_v09.py::test_v09_audit_slurm_scopes_nounset_around_conda_activation -q`
+
+Expected: FAIL for the state-diagnostics and replay launchers because they do not contain `set +u`.
+
+- [x] **Step 3: Apply the minimal launcher repair**
+
+```bash
+set -eo pipefail
+set +u
+source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
+conda activate nh_final
+set -u
+```
+
+- [x] **Step 4: Run the regression test and the complete training-audit test file**
+
+Run: `pytest src/26_historical_band_experts/tests/test_audit_formal_training_v09.py -q`
+
+Expected: PASS.
+
+- [x] **Step 5: Validate the shell file and commit only the launcher, test, and this plan**
+
+Run: `bash -n` separately for the three modified Slurm files.
+
+Commit message: `Fix: Scope nounset around audit environment activation`.
+
+### Task 2: Submit and register audit attempt 02
+
+**Files:**
+- Modify remotely through the Git mailbox only: `inbox/id26-v09-strict/cmd.sh`, `inbox/id26-v09-strict/seq`
+- Preserve: `/data1/home/sunyiq/v09_strict/logs/training_audit_202586.err`
+
+**Interfaces:**
+- Consumes: the new pushed audit-code commit and the absent `training_external_audit.json` precondition.
+- Produces: a new immutable job-id file for attempt 02 and one Slurm submission.
+
+- [ ] **Step 1: Fast-forward the isolated audit checkout to the exact new commit and verify it is clean**
+- [ ] **Step 2: Require job 202586 to remain `FAILED,1:0` and require the audit report to remain absent**
+- [ ] **Step 3: Submit `audit_formal_training_v09.slurm` once and write `training_audit_attempt_02_jobid.txt`**
+- [ ] **Step 4: Return immediately with the new job identifier and queue state; do not wait on the login node**
+- [ ] **Step 5: Resume the two-hour monitor with the new commit, job identifier, pass gates, and no automatic cleanup**
+
+## Self-Review
+
+- Spec coverage: the plan repairs only the observed launcher failure and preserves all scientific and evidence constraints.
+- Placeholder scan: no deferred implementation placeholders remain.
+- Type consistency: no Python interfaces or report schemas change.
+- Execution choice: the user already instructed Codex to solve recoverable problems autonomously, so execution continues inline in this session.
diff --git a/src/26_historical_band_experts/hpc/audit_formal_training_v09.slurm b/src/26_historical_band_experts/hpc/audit_formal_training_v09.slurm
index 61815403116735a4b97353c2e78eb85b7d31731e..ccd6b30c83239d506f49c00567d42d8bdff016d5 100644
--- a/src/26_historical_band_experts/hpc/audit_formal_training_v09.slurm
+++ b/src/26_historical_band_experts/hpc/audit_formal_training_v09.slurm
@@ -13 +13,2 @@
-set -euo pipefail
+set -eo pipefail
+set +u
@@ -15,0 +17 @@ conda activate nh_final
+set -u
diff --git a/src/26_historical_band_experts/hpc/audit_state_diagnostics_formal_v09.slurm b/src/26_historical_band_experts/hpc/audit_state_diagnostics_formal_v09.slurm
index e1ddb6bbbb5007143c8f73c11b4ea2fd38af0552..ab5a2cd8955524ffa5b4d9cef8e40812c7a9a9bd 100644
--- a/src/26_historical_band_experts/hpc/audit_state_diagnostics_formal_v09.slurm
+++ b/src/26_historical_band_experts/hpc/audit_state_diagnostics_formal_v09.slurm
@@ -13 +13,2 @@
-set -euo pipefail
+set -eo pipefail
+set +u
@@ -15,0 +17 @@ conda activate nh_final
+set -u
diff --git a/src/26_historical_band_experts/hpc/state_diagnostics_formal_v09.slurm b/src/26_historical_band_experts/hpc/state_diagnostics_formal_v09.slurm
index 76f4c1699b08c6646a6e7ff431ee48a27650e2f9..15a4b10c9d399cde91629b82c50b7304c4bc5cb8 100644
--- a/src/26_historical_band_experts/hpc/state_diagnostics_formal_v09.slurm
+++ b/src/26_historical_band_experts/hpc/state_diagnostics_formal_v09.slurm
@@ -13 +13,2 @@
-set -euo pipefail
+set -eo pipefail
+set +u
@@ -15,0 +17 @@ conda activate nh_final
+set -u
diff --git a/src/26_historical_band_experts/tests/test_audit_formal_training_v09.py b/src/26_historical_band_experts/tests/test_audit_formal_training_v09.py
index 212df8dbd67437e1935c1a4e8abfa39645d60266..aedc89e1fc94569ce030eaa5fabf4ae145e93a0a 100644
--- a/src/26_historical_band_experts/tests/test_audit_formal_training_v09.py
+++ b/src/26_historical_band_experts/tests/test_audit_formal_training_v09.py
@@ -20,0 +21,14 @@ _HASHES = {
+@pytest.mark.parametrize("filename", [
+    "audit_formal_training_v09.slurm",
+    "state_diagnostics_formal_v09.slurm",
+    "audit_state_diagnostics_formal_v09.slurm",
+])
+def test_v09_audit_slurm_scopes_nounset_around_conda_activation(filename):
+    script = (IDEA_ROOT / "hpc" / filename).read_text(encoding="utf-8")
+    disable_index = script.index("set +u")
+    activate_index = script.index("conda activate nh_final")
+    enable_index = script.index("set -u", activate_index)
+    audit_setup_index = script.index("AUDIT_REPO=")
+    assert disable_index < activate_index < enable_index < audit_setup_index
+
+
ID26_PATCH_59
  TREE=$(GIT_INDEX_FILE="$INDEX_FILE" git -C "$AUDIT_REPO" write-tree)
  echo "reconstructed_tree=$TREE"
  test "$TREE" = "$EXPECTED_TREE"
  export GIT_AUTHOR_NAME='yiqun.sun'
  export GIT_AUTHOR_EMAIL='44900555+yiqun-sun-rookie@users.noreply.github.com'
  export GIT_AUTHOR_DATE='1786452928 +0800'
  export GIT_COMMITTER_NAME='yiqun.sun'
  export GIT_COMMITTER_EMAIL='44900555+yiqun-sun-rookie@users.noreply.github.com'
  export GIT_COMMITTER_DATE='1786452928 +0800'
  NEW_COMMIT=$(git -C "$AUDIT_REPO" commit-tree "$TREE" -p "$PARENT" -m 'Fix: Scope nounset around audit environment activation')
  echo "reconstructed_commit=$NEW_COMMIT"
  test "$NEW_COMMIT" = "$COMMIT"
fi
test "$(git -C "$AUDIT_REPO" rev-parse "$COMMIT^{tree}")" = "$EXPECTED_TREE"
git -C "$AUDIT_REPO" checkout -q --detach "$COMMIT"
test "$(git -C "$AUDIT_REPO" rev-parse HEAD)" = "$COMMIT"
test -z "$(git -C "$AUDIT_REPO" status --porcelain --untracked-files=all)"
echo "audit_head=$(git -C "$AUDIT_REPO" rev-parse HEAD)"
if [ -f "$INDEX_FILE" ]; then sha256sum "$INDEX_FILE"; fi

echo "=== D SUBMIT TRAINING AUDIT ATTEMPT 02 ==="
JID=$(sbatch --parsable "$AUDIT_REPO/src/26_historical_band_experts/hpc/audit_formal_training_v09.slurm")
printf '%s\n' "$JID" > "$NEW_JOBID_FILE"
echo "TRAINING_AUDIT_ATTEMPT_02_JOBID=$JID"
squeue -j "$JID" -o '%.12i %.18j %.10T %.12M %.24R'
echo "=== END ==="
