#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf27_20260901
echo "=== DEPLOY ==="
mkdir -p $ROOT/logs $ROOT/results
sha256sum payload/kalmannet-tukf27/tukf27_hpc_payload_v1.tar.gz
tar -xzf payload/kalmannet-tukf27/tukf27_hpc_payload_v1.tar.gz -C $ROOT
echo "=== VERIFY MANIFEST ==="
python3 - <<'PYEOF'
import hashlib, json
root = "/data1/home/sunyiq/kalmannet_tukf27_20260901"
manifest = json.load(open(f"{root}/bundle_manifest.sha256.json"))
bad = 0
for rel, sha in manifest.items():
    if hashlib.sha256(open(f"{root}/{rel}","rb").read()).hexdigest() != sha:
        print("MISMATCH", rel); bad += 1
print(f"manifest_files={len(manifest)} mismatches={bad}")
raise SystemExit(1 if bad else 0)
PYEOF
sed -i 's/\r$//' $ROOT/slurm/*.slurm
cd $ROOT
out=$(sbatch $ROOT/slurm/tukf27_anchor.slurm 2>&1); echo "$out"
echo "$out" | grep -qE 'Submitted batch job [0-9]+' || { echo "SUBMIT_FAILED"; exit 1; }
echo "SEQ1_OK"
