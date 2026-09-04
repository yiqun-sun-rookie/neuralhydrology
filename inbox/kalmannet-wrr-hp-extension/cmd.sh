#!/bin/bash
set -eo pipefail
ROOT=/data1/home/sunyiq/kalmannet_wrr_hp_extension_20260902
REPO="$ROOT/repo"; EXP="$REPO/experiments/optimize_hyper_parameters/wrr_hp_extension_20260902"
TAR=/data1/home/sunyiq/hpc_mailbox/payload/kalmannet-wrr-hp-extension/v5/h4_addendum.tar.gz
STAMP=$(date +%Y%m%dT%H%M%S)
assert_sha256() { a="$(sha256sum "$2" | awk '{print $1}')"; [ "$a" = "$1" ] || { echo "SHA256_MISMATCH path=$2 expected=$1 actual=$a" >&2; exit 1; }; }
echo "=== PAYLOAD_CHECK ==="; assert_sha256 ffa81ec7dfaec7d43d07cb331285177e7ded7ff04bda9d477f16ea8fc2a8dd31 "$TAR"; echo payload_ok
echo "combos before: $(wc -l < "$EXP/combos.jsonl")"
echo "=== INSTALL ==="
cp -p "$EXP/combos.jsonl" "$EXP/combos.jsonl.bak_$STAMP"; cp -p "$EXP/source_manifest.json" "$EXP/source_manifest.json.bak_$STAMP"
mkdir -p "$ROOT/stage_$STAMP"; tar -xzf "$TAR" -C "$ROOT/stage_$STAMP"
S="$ROOT/stage_$STAMP/experiments/optimize_hyper_parameters/wrr_hp_extension_20260902"
assert_sha256 70d7616f219e53f09e476975bf32ac0ed0e3ca16c9f5ae9a572e8cb48e049d7c "$S/combos.jsonl"
assert_sha256 3e62596c1431e2a7878103c4d166815ebc8e46ddd0c5c5d46de3ab1e84078d1e "$S/source_manifest.json"
assert_sha256 ffe0108a7d4dfa939c42d433154cd2c80a35c4eb7018a5764f8ed94a54782a59 "$ROOT/stage_$STAMP/hpc_h4.slurm"
cp -f "$S/combos.jsonl" "$S/registry.csv" "$S/source_manifest.json" "$EXP/"
cp -f "$ROOT/stage_$STAMP/hpc_h4.slurm" "$ROOT/hpc_h4.slurm"; sed -i 's/\r$//' "$ROOT/hpc_h4.slurm"; chmod 700 "$ROOT/hpc_h4.slurm"
echo "combos after: $(wc -l < "$EXP/combos.jsonl")"; tail -n 3 "$EXP/combos.jsonl"
echo "=== VERIFY_DEPLOYED_TREE ==="
cd "$REPO"
python3 - <<'PY'
import hashlib, json, sys
from pathlib import Path
m=json.loads(Path("experiments/optimize_hyper_parameters/wrr_hp_extension_20260902/source_manifest.json").read_text())
bad=[(r,e) for r,e in m["source_sha256"].items() if hashlib.sha256(Path(r).read_bytes()).hexdigest().lower()!=e.lower()]
print(f"checked {len(m['source_sha256'])} files, mismatches={len(bad)}")
for b in bad: print("MISMATCH",b)
sys.exit(1 if bad else 0)
PY
echo "=== CURRENT_LOAD ==="; squeue -u "$USER" -h -t RUNNING -o '%i|%j' 2>&1 | sort || true
echo "=== SUBMIT ==="
cd "$ROOT"; OUT="$(sbatch "$ROOT/hpc_h4.slurm" 2>&1)"; echo "$OUT"
printf '%s\n' "$OUT" | grep -qE '^Submitted batch job [0-9]+$' || { echo SUBMIT_FAILED >&2; exit 1; }
JID="$(printf '%s\n' "$OUT" | awk '/^Submitted batch job [0-9]+$/{print $4; exit}')"
printf '%s' "$JID" > "$ROOT/h4_job_id.txt"; echo "h4_job_id=$JID"
squeue -j "$JID" -o '%i|%j|%T|%P|%R' || true
