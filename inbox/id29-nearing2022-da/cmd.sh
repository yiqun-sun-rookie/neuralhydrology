#!/bin/bash
# ID29 seq=57: install closure v2, fingerprint training data, and inspect the headline job.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
PAYLOAD=/data1/home/sunyiq/hpc_mailbox/payload/id29-nearing2022-da/closure_v2.tar.gz
EXPECTED_PAYLOAD_SHA=6254c2675654f3a29b541956bde03d20c127e6647bb9e2d8bab60eb4bf939551
PROVENANCE="$ROOT/closure_20260810/provenance"
MANIFEST="$PROVENANCE/hpc_camels_us_manifest.json"

echo "=== PAYLOAD ==="
echo "$EXPECTED_PAYLOAD_SHA  $PAYLOAD" | sha256sum -c -
echo "payload_members=$(tar -tzf "$PAYLOAD" | wc -l)"
tar -xzf "$PAYLOAD" -C "$ROOT"
test -f "$ROOT/src/29_nearing2022_da_ar/scripts/build_data_manifest.py"
test -f "$ROOT/src/29_nearing2022_da_ar/hpc/run_registered_training_array.slurm"
sha256sum "$ROOT/src/29_nearing2022_da_ar/registry/experiment_registry.csv"

echo "=== DATA MANIFEST ==="
mkdir -p "$PROVENANCE"
test ! -e "$MANIFEST"
python "$ROOT/src/29_nearing2022_da_ar/scripts/build_data_manifest.py" \
  --data-root "$ROOT/data/camels_us" \
  --basin-file "$ROOT/src/29_nearing2022_da_ar/basin_lists/531_basin_list.txt" \
  --expected-basins 531 \
  --output "$MANIFEST"
sha256sum "$MANIFEST"
echo "=== DATA_MANIFEST_BASE64_BEGIN ==="
base64 -w 76 "$MANIFEST"
echo "=== DATA_MANIFEST_BASE64_END ==="

echo "=== HEADLINE JOB 202214 ==="
if ! scontrol show job -dd 202214; then
  sacct -j 202214 --format=JobID,JobName,Partition,State,Elapsed,Start,End,ExitCode -P
fi
