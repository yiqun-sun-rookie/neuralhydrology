#!/bin/bash
set -eo pipefail
ROOT=/data1/home/sunyiq/kalmannet_wrr_hp_extension_20260902
REPO="$ROOT/repo"
EXP="$REPO/experiments/optimize_hyper_parameters/wrr_hp_extension_20260902"
TAR=/data1/home/sunyiq/hpc_mailbox/payload/kalmannet-wrr-hp-extension/v2/divcheck_addendum.tar.gz
STAMP=$(date +%Y%m%dT%H%M%S)

assert_sha256() {
  a="$(sha256sum "$2" | awk '{print $1}')"
  [ "$a" = "$1" ] || { echo "SHA256_MISMATCH path=$2 expected=$1 actual=$a" >&2; exit 1; }
}

echo "=== PAYLOAD_CHECK ==="
assert_sha256 b5e7e7e18f765c149529961ae62963aaca11c26a47393e069cfaf5cc70569b9b "$TAR"
echo payload_ok

echo "=== PRE_STATE ==="
echo "combos lines before: $(wc -l < "$EXP/combos.jsonl")"
squeue -j 218659 -h -o '%i|%T' 2>&1 | sort || true

echo "=== INSTALL ==="
cp -p "$EXP/combos.jsonl" "$EXP/combos.jsonl.bak_$STAMP"
cp -p "$EXP/source_manifest.json" "$EXP/source_manifest.json.bak_$STAMP"
mkdir -p "$ROOT/stage_$STAMP"
tar -xzf "$TAR" -C "$ROOT/stage_$STAMP"
assert_sha256 bc2841d968314f0f9b30a28a64aa3ac94f100cd1545feb85b624dff58efaddfa "$ROOT/stage_$STAMP/experiments/optimize_hyper_parameters/wrr_hp_extension_20260902/combos.jsonl"
assert_sha256 f6f04298895e7a95e4a2fb88a160a98ba2b2c0fab1967cfa4ff6b8efc14904ad "$ROOT/stage_$STAMP/experiments/optimize_hyper_parameters/wrr_hp_extension_20260902/source_manifest.json"
assert_sha256 f79dd590c91083eeebfdf7b802564924386959a1410d64543631e66b5457c7c4 "$ROOT/stage_$STAMP/hpc_single17.slurm"
cp -f "$ROOT/stage_$STAMP/experiments/optimize_hyper_parameters/wrr_hp_extension_20260902/combos.jsonl" "$EXP/combos.jsonl"
cp -f "$ROOT/stage_$STAMP/experiments/optimize_hyper_parameters/wrr_hp_extension_20260902/registry.csv" "$EXP/registry.csv"
cp -f "$ROOT/stage_$STAMP/experiments/optimize_hyper_parameters/wrr_hp_extension_20260902/source_manifest.json" "$EXP/source_manifest.json"
cp -f "$ROOT/stage_$STAMP/hpc_single17.slurm" "$ROOT/hpc_single17.slurm"
sed -i 's/\r$//' "$ROOT/hpc_single17.slurm"
chmod 700 "$ROOT/hpc_single17.slurm"
echo "combos lines after: $(wc -l < "$EXP/combos.jsonl")"
tail -n 1 "$EXP/combos.jsonl"

echo "=== VERIFY_DEPLOYED_TREE ==="
cd "$REPO"
python3 - <<'PY'
import hashlib, json, sys
from pathlib import Path
m = json.loads(Path("experiments/optimize_hyper_parameters/wrr_hp_extension_20260902/source_manifest.json").read_text())
bad = [(r, e, hashlib.sha256(Path(r).read_bytes()).hexdigest()) for r, e in m["source_sha256"].items()
       if hashlib.sha256(Path(r).read_bytes()).hexdigest().lower() != e.lower()]
print(f"checked {len(m['source_sha256'])} files, mismatches={len(bad)}")
for b in bad: print("MISMATCH", b)
sys.exit(1 if bad else 0)
PY

echo "=== SUBMIT ==="
cd "$ROOT"
OUT="$(sbatch "$ROOT/hpc_single17.slurm" 2>&1)"; echo "$OUT"
printf '%s\n' "$OUT" | grep -qE '^Submitted batch job [0-9]+$' || { echo SUBMIT_FAILED >&2; exit 1; }
JID="$(printf '%s\n' "$OUT" | awk '/^Submitted batch job [0-9]+$/{print $4; exit}')"
printf '%s' "$JID" > "$ROOT/divcheck_job_id.txt"
echo "divcheck_job_id=$JID"
squeue -j "$JID" -o '%i|%j|%T|%P|%R' || true
