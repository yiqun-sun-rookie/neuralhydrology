#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf26_20260831
echo "=== DEPLOY ==="
mkdir -p $ROOT/logs $ROOT/results
sha256sum payload/kalmannet-tukf26/tukf26_hpc_payload_v1.tar.gz
tar -xzf payload/kalmannet-tukf26/tukf26_hpc_payload_v1.tar.gz -C $ROOT
echo "=== VERIFY MANIFEST ==="
python3 - <<'PYEOF'
import hashlib, json
root = "/data1/home/sunyiq/kalmannet_tukf26_20260831"
manifest = json.load(open(f"{root}/bundle_manifest.sha256.json"))
bad = 0
for rel, sha in manifest.items():
    actual = hashlib.sha256(open(f"{root}/{rel}", "rb").read()).hexdigest()
    if actual != sha:
        print("MISMATCH", rel); bad += 1
print(f"manifest_files={len(manifest)} mismatches={bad}")
raise SystemExit(1 if bad else 0)
PYEOF
echo "=== FIX EOL + SBATCH ANCHOR ==="
sed -i 's/\r$//' $ROOT/slurm/*.slurm
cd $ROOT
out=$(sbatch $ROOT/slurm/tukf26_anchor.slurm 2>&1); echo "$out"
echo "$out" | grep -qE 'Submitted batch job [0-9]+' || { echo "SUBMIT_FAILED"; exit 1; }
echo "=== PARTITION STATE ==="
sinfo -p hcpu48y -o '%.10P %.6a %.6D %.10T' 2>/dev/null || true
squeue -u $USER 2>/dev/null | head -12 || true
echo "SEQ1_OK"
