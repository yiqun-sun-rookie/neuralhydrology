#!/bin/bash
# TUKF09-455 v2r6: deploy the probe-parser repair bundle to a brand-new remote root.
# Submits no job. Does not read, write or modify the v2r4 or v2r5 roots or the
# read-only training source capsule. No training. No formal evaluation.

set -o pipefail

ROOT6=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r6_20260902
ROOT5=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r5_20260901
ROOT4=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r4_20260901
PAY="$PWD/payload/kalmannet-tukf09-455/a800-exclusive-v2r6-probe-parser"
PY=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python

echo "=== SCOPE GUARD ==="
echo "NEW_ROOT=$ROOT6"
case "$ROOT6" in
  *v2r4*|*v2r5*|*training_source_capsule*) echo "SCOPE_GUARD_FAILED"; exit 1;;
esac
test "$ROOT6" != "$ROOT5" || { echo "SCOPE_GUARD_FAILED"; exit 1; }
echo "SCOPE_GUARD_OK"

echo "=== FROZEN FAILURE EVIDENCE UNCHANGED, READ ONLY ==="
ls -ld "$ROOT4" "$ROOT5" 2>&1
echo "V2R5_JOB_ID_FILE=$(cat "$ROOT5/status/training_job_id.txt" 2>&1)"
sha256sum "$ROOT5/logs/training-217939.out" "$ROOT5/logs/training-217939.err" 2>&1

echo "=== PAYLOAD EXACT GATE ==="
for f in "tukf09_455_basin_zero_validation_target_variance_revision_v1_hpc_execution_a800_exclusive_v2r6_formal_training.tar.gz" "bundle_manifest.sha256.json" "build_tukf09_455_a800_exclusive_hpc_bundle_v2r6.py"; do
  test -f "$PAY/$f" || { echo "PAYLOAD_MISSING $f"; exit 1; }
done
ARCHIVE_ACTUAL=$(sha256sum "$PAY/tukf09_455_basin_zero_validation_target_variance_revision_v1_hpc_execution_a800_exclusive_v2r6_formal_training.tar.gz" | cut -d' ' -f1)
MANIFEST_ACTUAL=$(sha256sum "$PAY/bundle_manifest.sha256.json" | cut -d' ' -f1)
BUILDER_ACTUAL=$(sha256sum "$PAY/build_tukf09_455_a800_exclusive_hpc_bundle_v2r6.py" | cut -d' ' -f1)
SIZE_ACTUAL=$(wc -c < "$PAY/tukf09_455_basin_zero_validation_target_variance_revision_v1_hpc_execution_a800_exclusive_v2r6_formal_training.tar.gz")
echo "ARCHIVE_SHA256=$ARCHIVE_ACTUAL"
echo "ARCHIVE_SIZE=$SIZE_ACTUAL"
echo "MANIFEST_SHA256=$MANIFEST_ACTUAL"
echo "BUILDER_SHA256=$BUILDER_ACTUAL"
test "$ARCHIVE_ACTUAL" = "a9d4effadaef3e836d657cd317051052377841b8a54c237ec9dc2457cc205e12" || { echo "ARCHIVE_HASH_MISMATCH"; exit 1; }
test "$SIZE_ACTUAL" = "9914609" || { echo "ARCHIVE_SIZE_MISMATCH"; exit 1; }
test "$MANIFEST_ACTUAL" = "f09046c1d1df3aeff19fdd0a034a6b5ba2199c18813c2906bed93d5beeb2bd64" || { echo "MANIFEST_HASH_MISMATCH"; exit 1; }
test "$BUILDER_ACTUAL" = "f86d917f953e5c4a9781774d6c29f0fbac42ecbb74014e034e19e83c03b016a2" || { echo "BUILDER_HASH_MISMATCH"; exit 1; }
echo "PAYLOAD_EXACT_GATE_PASS"

echo "=== EXCLUSIVE NEW ROOT RESERVATION ==="
if mkdir "$ROOT6" 2>/dev/null; then
  echo "NEW_ROOT_RESERVED"
else
  echo "NEW_ROOT_ALREADY_EXISTS_NOT_OVERWRITING"
  ls -ld "$ROOT6" 2>&1
  exit 1
fi
mkdir -p "$ROOT6/logs" "$ROOT6/status"

echo "=== EXTRACT ==="
"$PY" -B "$PAY/build_tukf09_455_a800_exclusive_hpc_bundle_v2r6.py" --archive "$PAY/tukf09_455_basin_zero_validation_target_variance_revision_v1_hpc_execution_a800_exclusive_v2r6_formal_training.tar.gz" --extract-to "$ROOT6/bundle" 2>&1

echo "=== STRICT EXTRACTED VERIFICATION ==="
"$PY" -B "$PAY/build_tukf09_455_a800_exclusive_hpc_bundle_v2r6.py" --verify-extracted "$ROOT6/bundle" 2>&1

echo "=== SURFACE ==="
ls -la "$ROOT6" 2>&1
ls -la "$ROOT6/bundle" 2>&1
find "$ROOT6/bundle" -type f | wc -l
echo "PROJECT_ROOT=$ROOT6/bundle/kalmannet"
sha256sum "$ROOT6/bundle/kalmannet/scripts/run_tukf09_455_neural_training_controller.py" 2>&1
sha256sum "$ROOT6/bundle/kalmannet/artifacts/tukf09_455_basin_zero_validation_target_variance_revision_v1/training_admission/training_admission.json" 2>&1

echo "=== MUTABLE TREES MUST STILL BE ABSENT ==="
test -e "$ROOT6/bundle/kalmannet/results/tukf09_455_basin_zero_validation_target_variance_revision_v1" && echo "RESULTS_PRESENT_UNEXPECTED" || echo "RESULTS_ABSENT_AS_REQUIRED"

echo "TUKF09_455_A800_EXCLUSIVE_V2R6_DEPLOYED_NO_JOB_SUBMITTED_FORMAL_EVALUATION_HOLD"
