#!/bin/bash
# id26-v09-strict seq=65: preserve failed state diagnostics attempt 01, reconstruct the exact deterministic-prefix fix, and submit attempt 02 once.
set -euo pipefail
export LC_ALL=C

ROOT=/data1/home/sunyiq/v09_strict
AUDIT_PARENT=$ROOT/audit_v09
AUDIT_REPO=$AUDIT_PARENT/neuralhydrology
TRAIN_REPO=$ROOT/codetest/neuralhydrology
STRICT_REPO=$ROOT/neuralhydrology
FORMAL_ROOT=$TRAIN_REPO/results/26_historical_band_experts/formal_v09
ATTEMPT_01_FILE=$AUDIT_PARENT/state_diagnostics_jobid.txt
ATTEMPT_02_FILE=$AUDIT_PARENT/state_diagnostics_attempt_02_jobid.txt
BUILDING_ROOT=$FORMAL_ROOT/state_diagnostics.building
FAILED_ROOT=$FORMAL_ROOT/state_diagnostics.attempt_01.job_204847.failed
PARENT=880a066d4b775e76a2e9b0358c393666c8737c6b
COMMIT=d69d2a7af509b141c7e8361f49f6fdeceed963af
EXPECTED_TREE=a0b5c46a37fcbdf16040e72f0dc94d53d6e1c5e0
INDEX_FILE=$AUDIT_PARENT/transport_seq65.index
export PATH=$ROOT/gitenv/bin:$PATH

echo "=== A PRESERVE FAILED ATTEMPT 01 ==="
JID1=$(tr -d '[:space:]' < "$ATTEMPT_01_FILE")
test "$JID1" = 204847
IFS='|' read -r STATE1 EXIT1 ELAPSED1 <<< "$(sacct -n -X -j "$JID1" --starttime 2026-08-18 --format=State,ExitCode,Elapsed -P)"
echo "attempt_01_jobid=$JID1 state=$STATE1 exit_code=$EXIT1 elapsed=$ELAPSED1"
test "$STATE1" = FAILED
test "$EXIT1" = 1:0
test -f "$ROOT/logs/state_diagnostics_204847.out"
test -f "$ROOT/logs/state_diagnostics_204847.err"
test ! -e "$FORMAL_ROOT/state_diagnostics"
test -d "$BUILDING_ROOT"
test ! -e "$FAILED_ROOT"
test ! -e "$ATTEMPT_02_FILE"
test ! -e "$FORMAL_ROOT/state_diagnostics_external_audit.json"
test ! -e "$FORMAL_ROOT/training_seal.json"
echo "attempt_01_building_inventory:"
find "$BUILDING_ROOT" -mindepth 1 -maxdepth 2 -print
mv -- "$BUILDING_ROOT" "$FAILED_ROOT"
test -d "$FAILED_ROOT"
test ! -e "$BUILDING_ROOT"
echo "attempt_01_archived=$FAILED_ROOT"

echo "=== B FROZEN CHECKOUTS AND TRAINING AUDIT ==="
TRAIN_HEAD=$(git -C "$TRAIN_REPO" rev-parse HEAD)
STRICT_HEAD=$(git -C "$STRICT_REPO" rev-parse HEAD)
echo "training_head=$TRAIN_HEAD"
echo "strict_head=$STRICT_HEAD"
test "$TRAIN_HEAD" = bb519b8b9980725ac1d5f4e298d76ae80ea2c58d
test "$STRICT_HEAD" = f94183209bf44ed6e672e1c23f98020905804e6d
test "$(sha256sum "$FORMAL_ROOT/training_external_audit.json" | cut -d' ' -f1)" = af6e424d6b88f53f5ad51f2ea76c4bfeb4a8bce408363c5909e952ec3ff80d9b

echo "=== C EXACT OFFLINE FIX RECONSTRUCTION ==="
test "$(git -C "$AUDIT_REPO" rev-parse HEAD)" = "$PARENT"
test -z "$(git -C "$AUDIT_REPO" status --porcelain --untracked-files=all)"
git -C "$AUDIT_REPO" cat-file -e "$PARENT^{commit}"
test ! -e "$INDEX_FILE"
GIT_INDEX_FILE="$INDEX_FILE" git -C "$AUDIT_REPO" read-tree "$PARENT"
GIT_INDEX_FILE="$INDEX_FILE" git -C "$AUDIT_REPO" apply --cached --unidiff-zero --whitespace=nowarn - <<'ID26_PATCH_65'
diff --git a/src/26_historical_band_experts/bands_formal_v09.py b/src/26_historical_band_experts/bands_formal_v09.py
index a5f145f5092b27237cf1bb931696317ed7f06ae2..af019bdd31d8880422a037cf71f34ec85580f57a 100644
--- a/src/26_historical_band_experts/bands_formal_v09.py
+++ b/src/26_historical_band_experts/bands_formal_v09.py
@@ -83,0 +84,10 @@ def _age_coordinate(low_lag: int, high_lag_exclusive: int) -> float:
+def _deterministic_cumsum_dim1_v09(values: torch.Tensor) -> torch.Tensor:
+    """Compute the dimension-one prefix sum with deterministic CUDA operations."""
+    running = torch.zeros_like(values[:, 0])
+    cumulative = []
+    for item in values.unbind(dim=1):
+        running = running + item
+        cumulative.append(running)
+    return torch.stack(cumulative, dim=1)
+
+
@@ -102 +112 @@ def split_windows_v09(windows: torch.Tensor) -> dict[str, torch.Tensor]:
-            torch.cumsum(windows, dim=1),
+            _deterministic_cumsum_dim1_v09(windows),
diff --git a/src/26_historical_band_experts/tests/test_bands_formal_v09.py b/src/26_historical_band_experts/tests/test_bands_formal_v09.py
index b02c3d11d2d77f5d67b5a61107834524097fcce3..01e1fcbe9d90d4922b353b415afcee60cd72f15e 100644
--- a/src/26_historical_band_experts/tests/test_bands_formal_v09.py
+++ b/src/26_historical_band_experts/tests/test_bands_formal_v09.py
@@ -103,0 +104,36 @@ def test_v09_split_is_causal_chronological_and_uses_exact_bin_means():
+def test_v09_split_does_not_call_torch_cumsum(monkeypatch):
+    from bands_formal_v09 import split_windows_v09
+
+    def reject_cumsum(*_args, **_kwargs):
+        raise AssertionError("split_windows_v09 must not call the nondeterministic CUDA cumsum kernel")
+
+    monkeypatch.setattr(torch, "cumsum", reject_cumsum)
+    windows = torch.arange(3_562 * 5, dtype=torch.float32).reshape(1, 3_562, 5)
+    dynamic = split_windows_v09(windows)
+
+    assert dynamic["recent"].shape == (1, 270, 5)
+    assert dynamic["history"].shape == (1, 120, 7)
+
+
+@pytest.mark.skipif(not torch.cuda.is_available(), reason="CUDA is required for the strict determinism regression")
+def test_v09_cuda_prefix_sum_is_strictly_deterministic_and_matches_native_cumsum():
+    from bands_formal_v09 import _deterministic_cumsum_dim1_v09
+
+    deterministic_before = torch.are_deterministic_algorithms_enabled()
+    warn_only_before = torch.is_deterministic_algorithms_warn_only_enabled()
+    try:
+        torch.manual_seed(26_090)
+        values = torch.randn(4, 3_562, 5, device="cuda", dtype=torch.float32)
+        torch.use_deterministic_algorithms(False)
+        native = torch.cumsum(values, dim=1)
+
+        torch.use_deterministic_algorithms(True)
+        first = _deterministic_cumsum_dim1_v09(values)
+        second = _deterministic_cumsum_dim1_v09(values)
+
+        assert torch.equal(first, second)
+        assert torch.equal(first, native)
+    finally:
+        torch.use_deterministic_algorithms(deterministic_before, warn_only=warn_only_before)
+
+
ID26_PATCH_65
TREE=$(GIT_INDEX_FILE="$INDEX_FILE" git -C "$AUDIT_REPO" write-tree)
echo "reconstructed_tree=$TREE"
test "$TREE" = "$EXPECTED_TREE"
export GIT_AUTHOR_NAME='yiqun.sun'
export GIT_AUTHOR_EMAIL='44900555+yiqun-sun-rookie@users.noreply.github.com'
export GIT_AUTHOR_DATE='1787648129 +0800'
export GIT_COMMITTER_NAME='yiqun.sun'
export GIT_COMMITTER_EMAIL='44900555+yiqun-sun-rookie@users.noreply.github.com'
export GIT_COMMITTER_DATE='1787648129 +0800'
RECONSTRUCTED_COMMIT=$(git -C "$AUDIT_REPO" commit-tree "$TREE" -p "$PARENT" -m 'Fix: Make version 09 CUDA prefix sums deterministic')
echo "reconstructed_commit=$RECONSTRUCTED_COMMIT"
test "$RECONSTRUCTED_COMMIT" = "$COMMIT"
test "$(git -C "$AUDIT_REPO" rev-parse "$COMMIT^{tree}")" = "$EXPECTED_TREE"
git -C "$AUDIT_REPO" checkout -q --detach "$COMMIT"
test "$(git -C "$AUDIT_REPO" rev-parse HEAD)" = "$COMMIT"
test -z "$(git -C "$AUDIT_REPO" status --porcelain --untracked-files=all)"
echo "audit_head=$(git -C "$AUDIT_REPO" rev-parse HEAD)"
sha256sum "$INDEX_FILE"

echo "=== D SUBMIT STATE DIAGNOSTICS ATTEMPT 02 ==="
JID2=$(sbatch --parsable "$AUDIT_REPO/src/26_historical_band_experts/hpc/state_diagnostics_formal_v09.slurm")
printf '%s\n' "$JID2" > "$ATTEMPT_02_FILE"
echo "STATE_DIAGNOSTICS_ATTEMPT_02_JOBID=$JID2"
squeue -j "$JID2" -o '%.12i %.18j %.12T %.12M %.24R' || true
echo "=== END ==="
