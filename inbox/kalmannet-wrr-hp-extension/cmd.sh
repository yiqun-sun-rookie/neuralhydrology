#!/bin/bash
set -eo pipefail
ROOT=/data1/home/sunyiq/kalmannet_wrr_hp_extension_20260902
REPO="$ROOT/repo"
EXP="$REPO/experiments/optimize_hyper_parameters/wrr_hp_extension_20260902"
TAR=/data1/home/sunyiq/hpc_mailbox/payload/kalmannet-wrr-hp-extension/v4/tiny_addendum.tar.gz
STAMP=$(date +%Y%m%dT%H%M%S)
assert_sha256() { a="$(sha256sum "$2" | awk '{print $1}')"; [ "$a" = "$1" ] || { echo "SHA256_MISMATCH path=$2 expected=$1 actual=$a" >&2; exit 1; }; }

echo "=== PAYLOAD_CHECK ==="
assert_sha256 46642444bd05bef21acfd0c25eb4561ff5f73e7d1f878acafa85c7151aa337eb "$TAR"; echo payload_ok
echo "combos lines before: $(wc -l < "$EXP/combos.jsonl")"

echo "=== INSTALL ==="
cp -p "$EXP/combos.jsonl" "$EXP/combos.jsonl.bak_$STAMP"
cp -p "$EXP/source_manifest.json" "$EXP/source_manifest.json.bak_$STAMP"
mkdir -p "$ROOT/stage_$STAMP"; tar -xzf "$TAR" -C "$ROOT/stage_$STAMP"
S="$ROOT/stage_$STAMP/experiments/optimize_hyper_parameters/wrr_hp_extension_20260902"
assert_sha256 ad56e84024e8c9bb0fa696400d72f617cd815923d36e768dbdbf81d2ebe1f6de "$S/combos.jsonl"
assert_sha256 1090423f2670f0b886d9720dc6137502b730115260daf95a9080955265616fd4 "$S/source_manifest.json"
assert_sha256 c590d444d21e0172029f27f3dfc43fea0d313fd0a96e83efaefda634de0f68e9 "$ROOT/stage_$STAMP/hpc_tiny.slurm"
cp -f "$S/combos.jsonl" "$S/registry.csv" "$S/source_manifest.json" "$EXP/"
cp -f "$ROOT/stage_$STAMP/hpc_tiny.slurm" "$ROOT/hpc_tiny.slurm"
sed -i 's/\r$//' "$ROOT/hpc_tiny.slurm"; chmod 700 "$ROOT/hpc_tiny.slurm"
echo "combos lines after: $(wc -l < "$EXP/combos.jsonl")"; tail -n 3 "$EXP/combos.jsonl"

echo "=== VERIFY_DEPLOYED_TREE ==="
cd "$REPO"
python3 - <<'PY'
import hashlib, json, sys
from pathlib import Path
m = json.loads(Path("experiments/optimize_hyper_parameters/wrr_hp_extension_20260902/source_manifest.json").read_text())
bad = [(r, e) for r, e in m["source_sha256"].items() if hashlib.sha256(Path(r).read_bytes()).hexdigest().lower() != e.lower()]
print(f"checked {len(m['source_sha256'])} files, mismatches={len(bad)}")
for b in bad: print("MISMATCH", b)
sys.exit(1 if bad else 0)
PY

echo "=== RUNNING_JOBS_BEFORE_SUBMIT ==="
squeue -j 220434 -h -o '%i|%T|%M' 2>&1 || true

echo "=== SUBMIT ==="
cd "$ROOT"
OUT="$(sbatch "$ROOT/hpc_tiny.slurm" 2>&1)"; echo "$OUT"
printf '%s\n' "$OUT" | grep -qE '^Submitted batch job [0-9]+$' || { echo SUBMIT_FAILED >&2; exit 1; }
JID="$(printf '%s\n' "$OUT" | awk '/^Submitted batch job [0-9]+$/{print $4; exit}')"
printf '%s' "$JID" > "$ROOT/tiny_job_id.txt"; echo "tiny_job_id=$JID"
squeue -j "$JID" -o '%i|%j|%T|%P|%R' || true
