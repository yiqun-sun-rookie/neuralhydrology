#!/bin/bash
set -eo pipefail
sequence=15

ROOT=/data1/home/sunyiq/regge_record_length_20260929_001
RUNTIME=$ROOT/runtime_probe_005
PAYLOAD=inbox/regge-record-length-20260929/payload/formal_calibration_capsule_001.tar.gz
DEPLOY=$ROOT/deploy
REMOTE_ARCHIVE=$DEPLOY/formal_calibration_capsule_001.tar.gz
CAPSULE=$DEPLOY/formal_calibration_capsule_001
STAGE=$DEPLOY/.formal_calibration_capsule_001_stage_seq15
OUTPUT=$ROOT/formal_calibration_001
ARCHIVE_SHA=c083b46bc5750f5163ffb1f616d52a8890ff54974d22dd26ef676cee4853cad5
MANIFEST_SHA=308d495cf7232d671eb09d2f0b651ad0bd3349585130ac2b7379f808d3da8a84

echo "=== exclusive formal deployment preflight ==="
test -x "$RUNTIME/bin/python"
test -f "$PAYLOAD"
test ! -e "$REMOTE_ARCHIVE"
test ! -e "$CAPSULE"
test ! -e "$STAGE"
test ! -e "$OUTPUT"
mkdir -p "$DEPLOY" "$ROOT/logs" "$ROOT/wrapper_receipts" "$ROOT/submission_receipts"

echo "=== copy and verify bound capsule archive ==="
"$RUNTIME/bin/python" - "$PAYLOAD" "$REMOTE_ARCHIVE" <<'PY'
from pathlib import Path
import shutil
import sys
source, target = map(Path, sys.argv[1:])
with source.open("rb") as opened, target.open("xb") as saved:
    shutil.copyfileobj(opened, saved, length=1024 * 1024)
PY
test "$(sha256sum "$REMOTE_ARCHIVE" | awk '{print $1}')" = "$ARCHIVE_SHA"
mkdir "$STAGE"
tar -xzf "$REMOTE_ARCHIVE" -C "$STAGE"
test -d "$STAGE/formal_calibration_capsule_001"
test "$(sha256sum "$STAGE/formal_calibration_capsule_001/capsule_manifest.json" | awk '{print $1}')" = "$MANIFEST_SHA"
mv -T "$STAGE/formal_calibration_capsule_001" "$CAPSULE"
rmdir "$STAGE"

echo "=== independent capsule verification on HPC ==="
export PYTHONPATH=$CAPSULE/project/python
export REGGE_CORE_ROOT=$CAPSULE/core
"$RUNTIME/bin/python" -u \
  "$CAPSULE/project/python/run_regge_record_length_hpc_calibration.py" \
  verify-capsule --capsule-root "$CAPSULE"

echo "=== submit exactly one formal science job ==="
SUBMITTED=$(sbatch --parsable "$CAPSULE/hpc/regge_record_length_calibration_20260929_001.slurm")
JOB_ID=${SUBMITTED%%;*}
case "$JOB_ID" in
  ''|*[!0-9]*) echo "INVALID_SUBMITTED_JOB_ID: $SUBMITTED"; exit 1 ;;
esac
SUBMISSION_RECEIPT=$ROOT/submission_receipts/formal_calibration_001-$JOB_ID.json
"$RUNTIME/bin/python" - "$SUBMISSION_RECEIPT" "$JOB_ID" "$ARCHIVE_SHA" "$MANIFEST_SHA" <<'PY'
from datetime import datetime, timezone
import json
from pathlib import Path
import sys
target, job_id, archive_sha, manifest_sha = sys.argv[1:]
payload = {
    "schema": "regge_record_length_hpc_submission_receipt_v01",
    "status": "submitted",
    "slurm_job_id": job_id,
    "archive_sha256": archive_sha,
    "capsule_manifest_sha256": manifest_sha,
    "retry_policy": "none",
    "submitted_utc": datetime.now(timezone.utc).isoformat(),
}
with Path(target).open("x", encoding="utf-8") as stream:
    json.dump(payload, stream, ensure_ascii=False, indent=2)
    stream.write("\n")
PY
echo "FORMAL_JOB_ID=$JOB_ID"
cat "$SUBMISSION_RECEIPT"
squeue -j "$JOB_ID" -o '%.18i %.24j %.9P %.10T %.30R'
echo "FORMAL_SUBMISSION_COMPLETE"
