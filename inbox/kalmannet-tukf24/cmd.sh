#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf24_20260827
echo "=== DEPLOY ==="
mkdir -p $ROOT/logs $ROOT/results
sha256sum payload/kalmannet-tukf24/tukf24_hpc_payload_v1.tar.gz
tar -xzf payload/kalmannet-tukf24/tukf24_hpc_payload_v1.tar.gz -C $ROOT
echo "=== VERIFY MANIFEST ==="
python3 - <<'PYEOF'
import hashlib, json
root = "/data1/home/sunyiq/kalmannet_tukf24_20260827"
manifest = json.load(open(f"{root}/bundle_manifest.sha256.json"))
bad = 0
for rel, sha in manifest.items():
    actual = hashlib.sha256(open(f"{root}/{rel}", "rb").read()).hexdigest()
    if actual != sha:
        print("MISMATCH", rel); bad += 1
print(f"manifest_files={len(manifest)} mismatches={bad}")
raise SystemExit(1 if bad else 0)
PYEOF
echo "=== SBATCH ANCHOR GATE ==="
cd $ROOT && sbatch $ROOT/slurm/tukf24_anchor.slurm
squeue -u $USER 2>/dev/null | head -10 || true
