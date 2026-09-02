#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf28_20260902
PAYLOAD=$(pwd)/payload/kalmannet-tukf28/tukf28_hpc_payload_v1.tar.gz

echo "=== DEPLOY ==="
[ -f "$PAYLOAD" ] || { echo "PAYLOAD_MISSING $PAYLOAD"; exit 1; }
sha256sum "$PAYLOAD"
mkdir -p $ROOT/logs $ROOT/results || exit 1
tar xzf "$PAYLOAD" -C $ROOT || exit 1

echo "=== VERIFY MANIFEST ==="
python - <<'PY'
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
if [ $? -ne 0 ]; then echo "MANIFEST_FAILED"; exit 1; fi

echo "=== SOURCE RECORDS ==="
echo "source_json=$(ls $ROOT/bundle/sources/*.json 2>/dev/null | wc -l)"

echo "=== SBATCH ANCHOR ==="
cd $ROOT || exit 1
sbatch $ROOT/slurm/tukf28_anchor.slurm || exit 1
echo SEQ2_OK
