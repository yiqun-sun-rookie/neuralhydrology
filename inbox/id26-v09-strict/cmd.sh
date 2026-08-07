#!/bin/bash
# id26-v09-strict seq=4 : locate the uploaded sealed-input tarball, verify, extract, verify again.
# Touches ONLY ~/v09_strict. No sbatch, no training, no authorization.
export LC_ALL=C
REPO="$HOME/v09_strict/neuralhydrology"
WANT_TAR_SHA="feee746c7bda7970c8bac470969bf4247118f8f35d6cf543a44a8a6b4bd1bed7"
DEST="$REPO/results/26_historical_band_experts/formal_v09"

echo "=== A LOCATE THE UPLOAD ==="
CANDIDATES=$(find "$HOME" -maxdepth 4 \
    \( -name 'v09_sealed_input.tar.gz' -o -name 'formal_v09.tar.gz' -o -name 'v09*.tar.gz' \) \
    -newermt '2026-08-07 14:40' 2>/dev/null | head -10)
if [ -z "$CANDIDATES" ]; then
  echo "no obvious name match; listing recent large files under \$HOME (depth<=3):"
  find "$HOME" -maxdepth 3 -type f -size +40M -newermt '2026-08-07 14:40' 2>/dev/null | head -15
else
  echo "$CANDIDATES"
fi

TAR=""
for c in $CANDIDATES; do
  s=$(sha256sum "$c" 2>/dev/null | cut -d' ' -f1)
  echo "  candidate: $c"
  echo "    size=$(stat -c%s "$c") sha256=$s"
  [ "$s" = "$WANT_TAR_SHA" ] && TAR="$c" && echo "    ^^ MATCHES EXPECTED HASH"
done

if [ -z "$TAR" ]; then
  echo "=== NO MATCHING TARBALL FOUND -- stopping, nothing changed ==="
  echo "expected sha256=$WANT_TAR_SHA"
  exit 0
fi

echo "=== B REFUSE TO CLOBBER ==="
if [ -e "$DEST" ] && [ -n "$(ls -A "$DEST" 2>/dev/null)" ]; then
  echo "destination already non-empty, refusing:"; ls -la "$DEST" | head; exit 1
fi
echo "destination clear"

echo "=== C EXTRACT ==="
tar xzf "$TAR" -C "$REPO" && echo "extracted"
echo "file count under formal_v09: $(find "$DEST" -type f 2>/dev/null | wc -l)  (want 19)"
find "$DEST" -type f 2>/dev/null | sed "s|$DEST/||" | sort

echo "=== D VERIFY THE FROZEN HASHES ==="
"$HOME/miniconda3/envs/nh_final/bin/python" - <<'PY' 2>&1 | tail -25
import hashlib, pathlib
base = pathlib.Path.home() / "v09_strict/neuralhydrology/results/26_historical_band_experts/formal_v09"
want = {
 "input_attempt_01/seal.json": "a5a64e43312ac303bf03ea3840e2cf126563527c6b82b8b94035c34978c25b3a",
 "input_attempt_01.external_audit.json": "e18be463df4cc6fe6c21a1e39c675f77db3e8c833109c1e9cfb557e37a832cd6",
 "input_attempt_01.trusted_source_external_audit.json": "81e3658fe27e8f658e59d81015ce3d1b2a3baef11045a3e22bd76254ef5d8387",
 "authorizations/formal_input_seal_authorization.json": "43b883940d58787d25b1a64bf1cee6097d459f3f95e595d59bea740a94b446d0",
 "formal_input_seal_authorization_consumed.json": "553cdbb8786735f7ac869982b4cb2a748b0f62e5241bd612fa59b0c69e871277",
 "inputs/training_targets.csv": "6abadf7172f1c8ebd48122a8abf68985d7d4f94b8c894371270208eeb45f2ebb",
 "inputs/training_targets.manifest.json": "3061d548fa0b9c81c8e3e25f0dbdd8cfbdb347aaea965ac6f6400c5f09da13e8",
}
bad = 0
for rel, exp in want.items():
    p = base / rel
    if not p.is_file():
        print(f"MISSING {rel}"); bad += 1; continue
    got = hashlib.sha256(p.read_bytes()).hexdigest()
    print(f"{'OK  ' if got==exp else 'DRIFT'} {rel}")
    bad += got != exp
print(f"frozen hash mismatches: {bad} (want 0)")
PY

echo "=== E SEALED FILE SET SELF-CHECK (seal.json inventory) ==="
"$HOME/miniconda3/envs/nh_final/bin/python" - <<'PY' 2>&1 | tail -8
import hashlib, json, pathlib
root = pathlib.Path.home() / "v09_strict/neuralhydrology/results/26_historical_band_experts/formal_v09/input_attempt_01"
seal = json.loads((root / "seal.json").read_text(encoding="utf-8"))
bad = 0
for item in seal["sealed_files"]:
    p = root / item["relative_path"].replace("\\", "/")
    if not p.is_file():
        print("MISSING", item["relative_path"]); bad += 1; continue
    if hashlib.sha256(p.read_bytes()).hexdigest() != item["sha256"]:
        print("DRIFT", item["relative_path"]); bad += 1
print(f"sealed files checked: {len(seal['sealed_files'])}, mismatches: {bad} (want 0)")
PY

echo "=== F WORKTREE STILL CLEAN? ==="
cd "$REPO" || exit 1
echo "dirty_files=$(git status --porcelain --untracked-files=all 2>/dev/null | wc -l)  (want 0)"

echo "=== G STAGE STATE (must be: no authorization, no consumption, no output) ==="
for p in "$DEST/authorizations/A09-NEST-01.authorization.json" \
         "$DEST/authorizations/A09-NEST-01.consumption.json" \
         "$DEST/strict_nesting" \
         "$DEST/R09-NEST-S100.legacy_checkpoint_bridge_external_audit.json" \
         "$DEST/R09-NEST-S100.training_resource_preflight_external_audit.json"; do
  [ -e "$p" ] && echo "PRESENT (BAD) $p" || echo "absent (good) $(basename "$p")"
done

echo "=== END ==="
