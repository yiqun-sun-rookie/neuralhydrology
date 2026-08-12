#!/bin/bash
# id26-v09-strict seq=61 : reconstruct the exact non-ASCII-path audit fix from an embedded Git patch and submit attempt 03 once.
set -euo pipefail
export LC_ALL=C
ROOT=/data1/home/sunyiq/v09_strict
AUDIT_PARENT=$ROOT/audit_v09
AUDIT_REPO=$AUDIT_PARENT/neuralhydrology
TRAIN_REPO=$ROOT/codetest/neuralhydrology
STRICT_REPO=$ROOT/neuralhydrology
FORMAL_ROOT=$TRAIN_REPO/results/26_historical_band_experts/formal_v09
ATTEMPT_01_FILE=$AUDIT_PARENT/training_audit_jobid.txt
ATTEMPT_02_FILE=$AUDIT_PARENT/training_audit_attempt_02_jobid.txt
ATTEMPT_03_FILE=$AUDIT_PARENT/training_audit_attempt_03_jobid.txt
REPORT=$FORMAL_ROOT/training_external_audit.json
PARENT=ac258afd31d835d93137da8961dc1206a1ee844c
COMMIT=880a066d4b775e76a2e9b0358c393666c8737c6b
EXPECTED_TREE=658227212b4b15158ffa85f39b0790d6b0c8cc27
INDEX_FILE=$AUDIT_PARENT/transport_seq61.index
export PATH=$ROOT/gitenv/bin:$PATH

echo "=== A PRESERVED EVIDENCE ==="
JID1=$(tr -d '[:space:]' < "$ATTEMPT_01_FILE")
JID2=$(tr -d '[:space:]' < "$ATTEMPT_02_FILE")
test "$JID1" = 202586
test "$JID2" = 202755
IFS='|' read -r STATE1 EXIT1 <<< "$(sacct -n -X -j "$JID1" --starttime 2026-08-11 --format=State,ExitCode -P)"
IFS='|' read -r STATE2 EXIT2 <<< "$(sacct -n -X -j "$JID2" --starttime 2026-08-12 --format=State,ExitCode -P)"
echo "attempt_01_jobid=$JID1 state=$STATE1 exit_code=$EXIT1"
echo "attempt_02_jobid=$JID2 state=$STATE2 exit_code=$EXIT2"
test "$STATE1" = FAILED
test "$EXIT1" = 1:0
test "$STATE2" = FAILED
test "$EXIT2" = 1:0
test ! -e "$ATTEMPT_03_FILE"
test ! -e "$REPORT"
test ! -e "$FORMAL_ROOT/state_diagnostics"
test ! -e "$FORMAL_ROOT/training_seal.json"

echo "=== B FROZEN CHECKOUTS ==="
TRAIN_HEAD=$(git -C "$TRAIN_REPO" rev-parse HEAD)
STRICT_HEAD=$(git -C "$STRICT_REPO" rev-parse HEAD)
echo "training_head=$TRAIN_HEAD"
echo "strict_head=$STRICT_HEAD"
test "$TRAIN_HEAD" = bb519b8b9980725ac1d5f4e298d76ae80ea2c58d
test "$STRICT_HEAD" = f94183209bf44ed6e672e1c23f98020905804e6d

echo "=== C EXACT OFFLINE COMMIT RECONSTRUCTION ==="
test "$(git -C "$AUDIT_REPO" rev-parse HEAD)" = "$PARENT"
test -z "$(git -C "$AUDIT_REPO" status --porcelain --untracked-files=all)"
git -C "$AUDIT_REPO" cat-file -e "$PARENT^{commit}"
test ! -e "$INDEX_FILE"
GIT_INDEX_FILE="$INDEX_FILE" git -C "$AUDIT_REPO" read-tree "$PARENT"
GIT_INDEX_FILE="$INDEX_FILE" git -C "$AUDIT_REPO" apply --cached --unidiff-zero --whitespace=nowarn - <<'ID26_PATCH_61'
diff --git a/docs/superpowers/plans/2026-08-11-id26-v09-training-audit-launcher-repair.md b/docs/superpowers/plans/2026-08-11-id26-v09-training-audit-launcher-repair.md
index 8e92501d7ea39cc03772c771177d106f07dada14..97cc002a13dbe9f0cb5d6eca8efa2bad15c428f0 100644
--- a/docs/superpowers/plans/2026-08-11-id26-v09-training-audit-launcher-repair.md
+++ b/docs/superpowers/plans/2026-08-11-id26-v09-training-audit-launcher-repair.md
@@ -88,5 +88,87 @@ Commit message: `Fix: Scope nounset around audit environment activation`.
-- [ ] **Step 1: Fast-forward the isolated audit checkout to the exact new commit and verify it is clean**
-- [ ] **Step 2: Require job 202586 to remain `FAILED,1:0` and require the audit report to remain absent**
-- [ ] **Step 3: Submit `audit_formal_training_v09.slurm` once and write `training_audit_attempt_02_jobid.txt`**
-- [ ] **Step 4: Return immediately with the new job identifier and queue state; do not wait on the login node**
-- [ ] **Step 5: Resume the two-hour monitor with the new commit, job identifier, pass gates, and no automatic cleanup**
+- [x] **Step 1: Fast-forward the isolated audit checkout to the exact new commit and verify it is clean**
+- [x] **Step 2: Require job 202586 to remain `FAILED,1:0` and require the audit report to remain absent**
+- [x] **Step 3: Submit `audit_formal_training_v09.slurm` once and write `training_audit_attempt_02_jobid.txt`**
+- [x] **Step 4: Return immediately with the new job identifier and queue state; do not wait on the login node**
+- [x] **Step 5: Resume the two-hour monitor with the new commit, job identifier, pass gates, and no automatic cleanup**
+
+### Task 3: Preserve non-ASCII tracked Git paths in the production source seal
+
+**Files:**
+- Modify: `src/26_historical_band_experts/audit_formal_training_v09.py`
+- Modify: `src/26_historical_band_experts/tests/test_audit_formal_training_v09.py`
+
+**Interfaces:**
+- Consumes: a Git worktree whose tracked paths may contain non-ASCII characters or newlines.
+- Produces: `_tracked_git_files(repo_root: Path) -> tuple[str, ...]`, using UTF-8-decoded, NUL-delimited
+  `git ls-files -z` output without display quoting.
+
+- [x] **Step 1: Add a regression test with a tracked Chinese path**
+
+```python
+def test_tracked_git_files_preserves_non_ascii_path(tmp_path):
+    from audit_formal_training_v09 import _tracked_git_files
+
+    repo = tmp_path / "repo"
+    subprocess.run(["git", "init", "-q", str(repo)], check=True)
+    relative = Path(".cursor/plans/全球水文模型论文计划_ee017201.plan.md")
+    path = repo / relative
+    path.parent.mkdir(parents=True)
+    path.write_text("plan\n", encoding="utf-8")
+    subprocess.run(["git", "-C", str(repo), "add", "--", relative.as_posix()], check=True)
+    assert _tracked_git_files(repo) == (relative.as_posix(),)
+```
+
+- [x] **Step 2: Run the focused test and verify it fails because the helper is absent**
+
+Run: `pytest src/26_historical_band_experts/tests/test_audit_formal_training_v09.py::test_tracked_git_files_preserves_non_ascii_path -q`
+
+Expected: FAIL with an import error for `_tracked_git_files`.
+
+- [x] **Step 3: Implement NUL-delimited tracked-path parsing and use it in the production source seal**
+
+```python
+def _tracked_git_files(repo_root: Path) -> tuple[str, ...]:
+    return tuple(value for value in _run_git(repo_root, "ls-files", "-z").split("\0") if value)
+```
+
+Configure `_run_git` with `encoding="utf-8"` and `errors="surrogateescape"`, then replace the line-oriented
+`git ls-files` parsing in `_production_source_seal` with `_tracked_git_files(repo_root)`.
+
+- [x] **Step 4: Run the focused test and the complete training-audit test file**
+
+Run: `pytest src/26_historical_band_experts/tests/test_audit_formal_training_v09.py -q`
+
+Expected: PASS.
+
+- [x] **Step 5: Commit the plan, regression test, and one-factor source fix**
+
+Commit message: `Fix: Preserve non-ASCII Git paths in training audit`.
+
+### Task 4: Submit training-audit attempt 03 from the verified source fix
+
+**Files:**
+- Modify remotely through the Git mailbox only: `inbox/id26-v09-strict/cmd.sh`, `inbox/id26-v09-strict/seq`
+- Preserve: `/data1/home/sunyiq/v09_strict/audit_v09/training_audit_attempt_02_jobid.txt`
+- Create remotely: `/data1/home/sunyiq/v09_strict/audit_v09/training_audit_attempt_03_jobid.txt`
+
+**Interfaces:**
+- Consumes: the exact Task-3 commit, its parent `ac258afd31d835d93137da8961dc1206a1ee844c`, and an embedded full-index Git patch.
+- Produces: a hash-verified audit checkout and one Slurm submission for attempt 03.
+
+- [ ] **Step 1: Generate the exact full-index patch and commit metadata**
+
+Run: `git diff -U0 --full-index --binary ac258afd31d835d93137da8961dc1206a1ee844c HEAD -- docs/superpowers/plans/2026-08-11-id26-v09-training-audit-launcher-repair.md src/26_historical_band_experts/audit_formal_training_v09.py src/26_historical_band_experts/tests/test_audit_formal_training_v09.py`
+
+- [ ] **Step 2: Embed the patch in the next single mailbox command**
+
+Use a new alternate index, `git read-tree`, `git apply --cached --unidiff-zero`, `git write-tree`, and `git commit-tree`; require both the reconstructed tree and commit to equal the local Task-3 commit before checkout.
+
+- [ ] **Step 3: Preserve attempts 01 and 02 and require the audit report to remain absent**
+
+Require job 202586 to remain `FAILED,1:0`, job 202755 to remain `FAILED,1:0`, and `training_external_audit.json` not to exist.
+
+- [ ] **Step 4: Submit the audit once and write `training_audit_attempt_03_jobid.txt`**
+
+Run remotely: `sbatch --parsable src/26_historical_band_experts/hpc/audit_formal_training_v09.slurm` from the exact reconstructed audit checkout.
+
+- [ ] **Step 5: Return immediately and resume two-hour monitoring of only the new job**
@@ -96 +178 @@ Commit message: `Fix: Scope nounset around audit environment activation`.
-- Spec coverage: the plan repairs only the observed launcher failure and preserves all scientific and evidence constraints.
+- Spec coverage: the plan repairs only the observed launcher and Git-path parsing failures and preserves all scientific and evidence constraints.
diff --git a/src/26_historical_band_experts/audit_formal_training_v09.py b/src/26_historical_band_experts/audit_formal_training_v09.py
index 8e2abd6ea74abee623f56e98164bb3b11f39eaa7..4157a7a6ca205411a628587972a16047ffaf7c17 100644
--- a/src/26_historical_band_experts/audit_formal_training_v09.py
+++ b/src/26_historical_band_experts/audit_formal_training_v09.py
@@ -469,0 +470,2 @@ def _run_git(repo_root: Path, *arguments: str) -> str:
+        encoding="utf-8",
+        errors="surrogateescape",
@@ -476,0 +479,4 @@ def _run_git(repo_root: Path, *arguments: str) -> str:
+def _tracked_git_files(repo_root: Path) -> tuple[str, ...]:
+    return tuple(value for value in _run_git(repo_root, "ls-files", "-z").split("\0") if value)
+
+
@@ -514 +520 @@ def _production_source_seal(formal_root: Path) -> dict:
-    tracked = [value for value in _run_git(repo_root, "ls-files").splitlines() if value]
+    tracked = _tracked_git_files(repo_root)
diff --git a/src/26_historical_band_experts/tests/test_audit_formal_training_v09.py b/src/26_historical_band_experts/tests/test_audit_formal_training_v09.py
index aedc89e1fc94569ce030eaa5fabf4ae145e93a0a..d5d0d45632e1a908adfb7a79f750e5dc6ba34909 100644
--- a/src/26_historical_band_experts/tests/test_audit_formal_training_v09.py
+++ b/src/26_historical_band_experts/tests/test_audit_formal_training_v09.py
@@ -4,0 +5 @@ from pathlib import Path
+import subprocess
@@ -34,0 +36,13 @@ def test_v09_audit_slurm_scopes_nounset_around_conda_activation(filename):
+def test_tracked_git_files_preserves_non_ascii_path(tmp_path):
+    from audit_formal_training_v09 import _tracked_git_files
+
+    repo = tmp_path / "repo"
+    subprocess.run(["git", "init", "-q", str(repo)], check=True)
+    relative = Path(".cursor/plans/全球水文模型论文计划_ee017201.plan.md")
+    path = repo / relative
+    path.parent.mkdir(parents=True)
+    path.write_text("plan\n", encoding="utf-8")
+    subprocess.run(["git", "-C", str(repo), "add", "--", relative.as_posix()], check=True)
+    assert _tracked_git_files(repo) == (relative.as_posix(),)
+
+
ID26_PATCH_61
TREE=$(GIT_INDEX_FILE="$INDEX_FILE" git -C "$AUDIT_REPO" write-tree)
echo "reconstructed_tree=$TREE"
test "$TREE" = "$EXPECTED_TREE"
export GIT_AUTHOR_NAME='yiqun.sun'
export GIT_AUTHOR_EMAIL='44900555+yiqun-sun-rookie@users.noreply.github.com'
export GIT_AUTHOR_DATE='1786496786 +0800'
export GIT_COMMITTER_NAME='yiqun.sun'
export GIT_COMMITTER_EMAIL='44900555+yiqun-sun-rookie@users.noreply.github.com'
export GIT_COMMITTER_DATE='1786496786 +0800'
RECONSTRUCTED_COMMIT=$(git -C "$AUDIT_REPO" commit-tree "$TREE" -p "$PARENT" -m 'Fix: Preserve non-ASCII Git paths in training audit')
echo "reconstructed_commit=$RECONSTRUCTED_COMMIT"
test "$RECONSTRUCTED_COMMIT" = "$COMMIT"
test "$(git -C "$AUDIT_REPO" rev-parse "$COMMIT^{tree}")" = "$EXPECTED_TREE"
git -C "$AUDIT_REPO" checkout -q --detach "$COMMIT"
test "$(git -C "$AUDIT_REPO" rev-parse HEAD)" = "$COMMIT"
test -z "$(git -C "$AUDIT_REPO" status --porcelain --untracked-files=all)"
echo "audit_head=$(git -C "$AUDIT_REPO" rev-parse HEAD)"
sha256sum "$INDEX_FILE"

echo "=== D SUBMIT TRAINING AUDIT ATTEMPT 03 ==="
JID3=$(sbatch --parsable "$AUDIT_REPO/src/26_historical_band_experts/hpc/audit_formal_training_v09.slurm")
printf '%s\n' "$JID3" > "$ATTEMPT_03_FILE"
echo "TRAINING_AUDIT_ATTEMPT_03_JOBID=$JID3"
squeue -j "$JID3" -o '%.12i %.18j %.10T %.12M %.24R' || true
echo "=== END ==="
