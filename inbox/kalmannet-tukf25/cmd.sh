#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf25_20260831
echo "=== GUARD ==="
[ -d "$ROOT/bundle" ] && echo "ALREADY_DEPLOYED (will overwrite bundle files only)"
mkdir -p $ROOT/logs $ROOT/results
echo "=== DEPLOY ==="
sha256sum payload/kalmannet-tukf25/tukf25_hpc_payload_v1.tar.gz
tar -xzf payload/kalmannet-tukf25/tukf25_hpc_payload_v1.tar.gz -C $ROOT
sed -i 's/\r$//' $ROOT/slurm/*.slurm
echo "=== VERIFY MANIFEST ==="
python3 - <<'PYEOF'
import hashlib, json
root = "/data1/home/sunyiq/kalmannet_tukf25_20260831"
manifest = json.load(open(f"{root}/bundle_manifest.sha256.json"))
bad = 0
for rel, sha in manifest.items():
    actual = hashlib.sha256(open(f"{root}/{rel}", "rb").read()).hexdigest()
    if actual != sha:
        print("MISMATCH", rel); bad += 1
print(f"manifest_files={len(manifest)} mismatches={bad}")
raise SystemExit(1 if bad else 0)
PYEOF
RC=$?
[ "$RC" = "0" ] || { echo MANIFEST_FAILED; exit 1; }
echo "=== DATA ROOT CHECK ==="
ls -d /data1/home/sunyiq/neuralhydrology/data/camels_us 2>&1 | head -2
echo "=== PARTITION hcpu48y ==="
sinfo -p hcpu48y -o "%.10P %.6a %.6D %.6t %.30N" 2>&1 || true
echo "=== MY QUEUE BEFORE ==="
squeue -u $USER 2>/dev/null | head -12 || true
echo "=== SBATCH ANCHOR GATE ==="
out=$(sbatch $ROOT/slurm/tukf25_anchor.slurm 2>&1); echo "$out"
echo "$out" | grep -qE 'Submitted batch job [0-9]+' || { echo "SUBMIT_FAILED"; exit 1; }
echo "SEQ1_OK"
