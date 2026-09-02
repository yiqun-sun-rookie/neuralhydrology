#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf28_20260902
MBX=$(cd "$(dirname "$0")/../.." && pwd)

echo "=== RESOURCES (hcpu48y) ==="
sinfo -p hcpu48y -o "%P %a %l %D %t %C %m" 2>/dev/null | head -10
echo "--- my jobs ---"
squeue -u $USER -h -o "%i %j %T %P" 2>/dev/null | head -20 || true
echo "--- queue depth on hcpu48y ---"
squeue -p hcpu48y -h -o "%T" 2>/dev/null | sort | uniq -c || true
echo "--- disk ---"
df -h /data1/home/sunyiq 2>/dev/null | tail -1

echo "=== DEPLOY ==="
mkdir -p $ROOT/logs $ROOT/results || exit 1
sha256sum $MBX/payload/kalmannet-tukf28/tukf28_hpc_payload_v1.tar.gz
tar xzf $MBX/payload/kalmannet-tukf28/tukf28_hpc_payload_v1.tar.gz -C $ROOT || exit 1

echo "=== VERIFY MANIFEST ==="
cd $ROOT && python - <<'PY'
import hashlib, json, pathlib
root = pathlib.Path('/data1/home/sunyiq/kalmannet_tukf28_20260902')
man = json.loads((root / 'bundle_manifest.sha256.json').read_text())
bad = [k for k, v in man.items()
       if hashlib.sha256((root / k).read_bytes()).hexdigest() != v]
print('manifest_files=%d mismatches=%d' % (len(man), len(bad)))
for k in bad[:10]:
    print('  MISMATCH', k)
raise SystemExit(1 if bad else 0)
PY
[ $? -ne 0 ] && { echo "MANIFEST_FAILED"; exit 1; }

echo "=== SOURCE RECORDS ==="
ls $ROOT/bundle/sources/*.json | wc -l

echo "=== SBATCH ANCHOR ==="
sbatch $ROOT/slurm/tukf28_anchor.slurm || exit 1
echo SEQ1_OK
