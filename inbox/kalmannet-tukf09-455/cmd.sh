#!/bin/bash
# TUKF09-455: package the finished v2r14 result root for retrieval to the Windows workstation.
# The result root itself is read only here. The archive lands in $ROOT/export, outside the
# result root, so the root's own top-level surface stays exactly as the seal expects.
set -eo pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r14_20260909
R="$ROOT/bundle/kalmannet/results/tukf09_455_basin_zero_validation_target_variance_revision_v1"
E="$ROOT/export"
echo "TIME=$(date -Is)"

echo "=== PRECONDITIONS ==="
test -d "$R" || { echo RESULT_ROOT_MISSING; exit 20; }
test ! -e "$E/tukf09_455_v2r14_result_root_20260912.tar" || { echo ARCHIVE_ALREADY_EXISTS; exit 21; }
test ! -e "$R/selection" -a ! -e "$R/independent" || { echo ALREADY_SEALED_HERE; exit 22; }
test ! -e "$R/control/.training_phase.lock" || { echo PHASE_LOCK_PRESENT; exit 23; }
echo "FILES_BEFORE=$(find "$R" -type f | wc -l)  BYTES_BEFORE=$(du -sb "$R" | cut -f1)"

echo "=== PER-FILE HASH MANIFEST OF THE RESULT ROOT (read only) ==="
mkdir -p "$E"
(cd "$R" && find . -type f | LC_ALL=C sort | xargs -d "
" sha256sum) > "$E/result_root.sha256"
echo "MANIFEST_LINES=$(wc -l < "$E/result_root.sha256")"

echo "=== TAR THE RESULT ROOT (no compression; checkpoints do not compress) ==="
tar --format=gnu --no-xattrs --numeric-owner -C "$(dirname "$R")" -cf "$E/tukf09_455_v2r14_result_root_20260912.tar" "tukf09_455_basin_zero_validation_target_variance_revision_v1"
(cd "$E" && sha256sum "tukf09_455_v2r14_result_root_20260912.tar" > "tukf09_455_v2r14_result_root_20260912.tar.sha256")
ls -la "$E"
cat "$E/tukf09_455_v2r14_result_root_20260912.tar.sha256"
echo "TAR_MEMBERS=$(tar -tf "$E/tukf09_455_v2r14_result_root_20260912.tar" | grep -vc "/$")"

echo "=== THE RESULT ROOT IS UNCHANGED ==="
echo "FILES_AFTER=$(find "$R" -type f | wc -l)  BYTES_AFTER=$(du -sb "$R" | cut -f1)"
ls "$R"

echo TUKF09_455_V2R14_RESULT_ROOT_PACKAGED_FOR_RETRIEVAL
