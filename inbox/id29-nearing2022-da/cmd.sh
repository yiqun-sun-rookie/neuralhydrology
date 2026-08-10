#!/bin/bash
# ID29 seq=73: strengthen final manifest with evaluation logs and verify pending job inputs.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
PAYLOAD=/data1/home/sunyiq/hpc_mailbox/payload/id29-nearing2022-da/closure_v9.tar.gz
EXPECTED_PAYLOAD_SHA=ee67b01649f17a322137d2b4457521317476c6a189a9b182e5923908e268091e
VERIFIER="$ROOT/src/29_nearing2022_da_ar/scripts/verify_registered_closure.py"
DATA_MANIFEST="$ROOT/closure_20260810/provenance/hpc_camels_us_manifest_v2.json"

echo "=== INSTALL ==="
echo "$EXPECTED_PAYLOAD_SHA  $PAYLOAD" | sha256sum -c -
test "$(tar -tzf "$PAYLOAD" | wc -l)" -eq 1
tar -xzf "$PAYLOAD" -C "$ROOT"
echo "c5f994524fb2c1ecc92fad9509a8fa51f7299d2cb0d22c432c9c54a6e8385136  $VERIFIER" | sha256sum -c -
test -f "$DATA_MANIFEST"
sha256sum "$DATA_MANIFEST"

echo "=== FAIL-CLOSED STATUS ==="
source ~/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
cd "$ROOT"
export PYTHONPATH="$ROOT${PYTHONPATH:+:$PYTHONPATH}"
STATUS=$(mktemp)
set +e
python "$VERIFIER" \
  --repo-root "$ROOT" \
  --training-registry "$ROOT/src/29_nearing2022_da_ar/registry/experiment_registry.csv" \
  --evaluation-registry "$ROOT/src/29_nearing2022_da_ar/registry/evaluation_registry.csv" \
  --hyperparameter-registry "$ROOT/src/29_nearing2022_da_ar/registry/assimilation_hyperparameter_registry.csv" \
  --evaluation-aggregation-dir "$ROOT/closure_20260810/aggregation/evaluations" \
  --hyperparameter-aggregation-dir "$ROOT/closure_20260810/aggregation/hyperparameters" > "$STATUS"
STATUS_RC=$?
set -e
test "$STATUS_RC" -eq 2
grep -q '"complete": false' "$STATUS"
grep -q '"training": 46' "$STATUS"
grep -q '"evaluations": 180' "$STATUS"
grep -q '"hyperparameters": 660' "$STATUS"
sed -n '1,16p' "$STATUS"
rm -f "$STATUS"

echo "=== PENDING FINAL GATE ==="
squeue -j 202229,202230,202242 -o '%.18i %.24j %.2t %.10M %.6D %R'
scontrol show job -o 202242 | sed -n 's/.*Dependency=\([^ ]*\).*/manifest_dependency=\1/p'
