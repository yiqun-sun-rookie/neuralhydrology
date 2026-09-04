#!/bin/bash
set -eo pipefail
ROOT=/data1/home/sunyiq/kalmannet_wrr_hp_extension_20260902
REPO="$ROOT/repo"
EXP="$REPO/experiments/optimize_hyper_parameters/wrr_hp_extension_20260902"
TAR=/data1/home/sunyiq/hpc_mailbox/payload/kalmannet-wrr-hp-extension/v3/small_addendum.tar.gz
STAMP=$(date +%Y%m%dT%H%M%S)
assert_sha256() { a="$(sha256sum "$2" | awk '{print $1}')"; [ "$a" = "$1" ] || { echo "SHA256_MISMATCH path=$2 expected=$1 actual=$a" >&2; exit 1; }; }

echo "=== PAYLOAD_CHECK ==="
assert_sha256 47cc5d81196c50397b2a75944b06b5a9f81e0d8329c10606917d949cd4df9a23 "$TAR"; echo payload_ok
echo "combos lines before: $(wc -l < "$EXP/combos.jsonl")"

echo "=== INSTALL ==="
cp -p "$EXP/combos.jsonl" "$EXP/combos.jsonl.bak_$STAMP"
cp -p "$EXP/source_manifest.json" "$EXP/source_manifest.json.bak_$STAMP"
mkdir -p "$ROOT/stage_$STAMP"; tar -xzf "$TAR" -C "$ROOT/stage_$STAMP"
S="$ROOT/stage_$STAMP/experiments/optimize_hyper_parameters/wrr_hp_extension_20260902"
assert_sha256 1f9b67cb1f05b040e35bf0147ba8e0737807b4733df9ef5a1125750892238a58 "$S/combos.jsonl"
assert_sha256 a055868289c2f68d9f3f58d8516ad40c59dfbcbc7e836ddaf2aa907b3e1bc22e "$S/source_manifest.json"
assert_sha256 fd23f4b5a01f96a6907b23bfa9dd2ccc07aee7459d3b2cfb17be4c37065cbe07 "$ROOT/stage_$STAMP/hpc_small.slurm"
cp -f "$S/combos.jsonl" "$S/registry.csv" "$S/source_manifest.json" "$EXP/"
cp -f "$ROOT/stage_$STAMP/hpc_small.slurm" "$ROOT/hpc_small.slurm"
sed -i 's/\r$//' "$ROOT/hpc_small.slurm"; chmod 700 "$ROOT/hpc_small.slurm"
echo "combos lines after: $(wc -l < "$EXP/combos.jsonl")"; tail -n 2 "$EXP/combos.jsonl"

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

echo "=== SUBMIT ==="
cd "$ROOT"
OUT="$(sbatch "$ROOT/hpc_small.slurm" 2>&1)"; echo "$OUT"
printf '%s\n' "$OUT" | grep -qE '^Submitted batch job [0-9]+$' || { echo SUBMIT_FAILED >&2; exit 1; }
JID="$(printf '%s\n' "$OUT" | awk '/^Submitted batch job [0-9]+$/{print $4; exit}')"
printf '%s' "$JID" > "$ROOT/small_job_id.txt"; echo "small_job_id=$JID"
squeue -j "$JID" -o '%i|%j|%T|%P|%R' || true
