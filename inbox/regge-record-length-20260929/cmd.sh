#!/bin/bash
set -eo pipefail

sequence=27
ROOT=/data1/home/sunyiq/regge_record_length_20260929_001
RUNTIME=$ROOT/runtime_probe_005
PAYLOAD=inbox/regge-record-length-20260929/payload/formal_calibration_capsule_004.tar.gz
DEPLOY=$ROOT/deploy
REMOTE_ARCHIVE=$DEPLOY/formal_calibration_capsule_004.tar.gz
CAPSULE=$DEPLOY/formal_calibration_capsule_004
STAGE=$DEPLOY/.formal_calibration_capsule_004_stage_seq27
OUTPUT=$ROOT/formal_calibration_004
PACKAGE=$ROOT/transport_package_004
CREDENTIALS=$ROOT/transport_credentials_004
SUBMISSION_RECEIPTS=$ROOT/submission_receipts
WRAPPER_RECEIPTS=$ROOT/wrapper_receipts
DEPLOYMENT_RECEIPTS=$ROOT/deployment_receipts
DEPLOYMENT_FAILURE=$DEPLOYMENT_RECEIPTS/formal_calibration_004-seq27.failed.json
ARCHIVE_SHA=9e1af0c4ff190f27aeaab34001db22b3d2328031439911526272a6982394045b
ARCHIVE_BYTES=1532549
MANIFEST_SHA=c31b04606f162bb777bed6943297aea7934b5e2c93db63601de32b25147a2efc
AUTHORIZATION_SHA=80d815cd4ee52a63cf5f67e38372c07b246f80e5cf8da6d743e5f3609fa78376
HPC_PUBLIC_SHA=64d95166c7614c103ec0a33b8791f0f810a59ecea36d7efe21bd87fb792f2817
CURRENT_STAGE=preflight
SUBMITTED_JOB_ID=
JOB_SUBMITTED=false
MANUAL_RECONCILIATION_REQUIRED=false

export PYTHONDONTWRITEBYTECODE=1

mkdir -p "$DEPLOY" "$ROOT/logs" "$SUBMISSION_RECEIPTS" \
  "$WRAPPER_RECEIPTS" "$DEPLOYMENT_RECEIPTS"
test ! -e "$DEPLOYMENT_FAILURE"

persist_deployment_failure() {
  rc=$1
  if [ "$rc" -ne 0 ] && [ ! -e "$DEPLOYMENT_FAILURE" ]; then
    temporary=$DEPLOYMENT_FAILURE.tmp.$$
    umask 077
    printf '{"schema":"regge_record_length_hpc_deployment_failure_v01","status":"failed","passed":false,"sequence":27,"stage":"%s","exit_code":%s,"job_submitted":%s,"submitted_job_id":"%s","manual_reconciliation_required":%s,"automatic_retry":false}\n' \
      "$CURRENT_STAGE" "$rc" "$JOB_SUBMITTED" "$SUBMITTED_JOB_ID" \
      "$MANUAL_RECONCILIATION_REQUIRED" > "$temporary"
    mv -n "$temporary" "$DEPLOYMENT_FAILURE"
  fi
}

on_error() {
  rc=$?
  trap - ERR
  persist_deployment_failure "$rc"
  exit "$rc"
}
trap on_error ERR

echo "=== exclusive attempt-004 deployment preflight ==="
if ! DEPLOYMENT_MATCHES=$(find "$DEPLOYMENT_RECEIPTS" -maxdepth 1 -type f \
    -name 'formal_calibration_004-*.json' -print); then
  echo "DEPLOYMENT_RECEIPT_SCAN_FAILED"
  false
fi
test -z "$DEPLOYMENT_MATCHES"
if ! SUBMISSION_MATCHES=$(find "$SUBMISSION_RECEIPTS" -maxdepth 1 -type f \
    -name 'formal_calibration_004-*.json' -print); then
  echo "SUBMISSION_RECEIPT_SCAN_FAILED"
  false
fi
test -z "$SUBMISSION_MATCHES"
if ! WRAPPER_MATCHES=$(find "$WRAPPER_RECEIPTS" -maxdepth 1 -type f \
    -name 'formal_calibration_004-*.failed.json' -print); then
  echo "WRAPPER_RECEIPT_SCAN_FAILED"
  false
fi
test -z "$WRAPPER_MATCHES"
test -x "$RUNTIME/bin/python"
test -f "$PAYLOAD"
test "$(stat -c '%s' "$PAYLOAD")" = "$ARCHIVE_BYTES"
test "$(sha256sum "$PAYLOAD" | awk '{print $1}')" = "$ARCHIVE_SHA"
test -f "$CREDENTIALS/upload_token_private.pem"
test -f "$CREDENTIALS/upload_token_public.pem"
test "$(stat -c '%a' "$CREDENTIALS/upload_token_private.pem")" = "600"
test "$(sha256sum "$CREDENTIALS/upload_token_public.pem" | awk '{print $1}')" = "$HPC_PUBLIC_SHA"
test "$(openssl pkey -in "$CREDENTIALS/upload_token_private.pem" -pubout \
  | sha256sum | awk '{print $1}')" = "$HPC_PUBLIC_SHA"
test ! -e "$REMOTE_ARCHIVE"
test ! -e "$CAPSULE"
test ! -e "$STAGE"
test ! -e "$OUTPUT"
test ! -e "$PACKAGE"
EXISTING_JOB=$(squeue -h -n regge_rl_cal_004 -o '%A')
test -z "$EXISTING_JOB"

CURRENT_STAGE=copy_archive
"$RUNTIME/bin/python" -B - "$PAYLOAD" "$REMOTE_ARCHIVE" <<'PY'
from pathlib import Path
import shutil
import sys

source, target = map(Path, sys.argv[1:])
with source.open("rb") as opened, target.open("xb") as saved:
    shutil.copyfileobj(opened, saved, length=1024 * 1024)
PY
test "$(stat -c '%s' "$REMOTE_ARCHIVE")" = "$ARCHIVE_BYTES"
test "$(sha256sum "$REMOTE_ARCHIVE" | awk '{print $1}')" = "$ARCHIVE_SHA"

CURRENT_STAGE=extract_capsule
mkdir "$STAGE"
tar -xzf "$REMOTE_ARCHIVE" -C "$STAGE"
test -d "$STAGE/formal_calibration_capsule_004"
test "$(sha256sum "$STAGE/formal_calibration_capsule_004/capsule_manifest.json" | awk '{print $1}')" = "$MANIFEST_SHA"
mv -T "$STAGE/formal_calibration_capsule_004" "$CAPSULE"
rmdir "$STAGE"

CURRENT_STAGE=verify_capsule
export PYTHONPATH=$CAPSULE/project/python
export REGGE_CORE_ROOT=$CAPSULE/core
"$RUNTIME/bin/python" -B -u \
  "$CAPSULE/project/python/run_regge_record_length_hpc_calibration.py" \
  verify-capsule --capsule-root "$CAPSULE"
"$RUNTIME/bin/python" -B - "$CAPSULE/calibration_authorization.json" <<'PY'
import json
from pathlib import Path
import sys

authorization = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
paths = [
    authorization["runtime_root"],
    authorization["runtime_ready_path"],
    authorization["runtime_freeze_path"],
]
if authorization.get("formal_attempt") != "20260929-004":
    raise SystemExit("formal attempt differs")
if any(not value.startswith("/data1/") or "\\" in value for value in paths):
    raise SystemExit("remote path is not a POSIX absolute path")
print("REMOTE_POSIX_PATH_GATE=PASS")
PY
if ! BYTECODE_MATCH=$(find "$CAPSULE" -type d \
    -name __pycache__ -print -quit); then
  echo "BYTECODE_SCAN_FAILED"
  false
fi
test -z "$BYTECODE_MATCH"
test "$(sha256sum "$CAPSULE/capsule_manifest.json" | awk '{print $1}')" = "$MANIFEST_SHA"
test "$(sha256sum "$CAPSULE/calibration_authorization.json" | awk '{print $1}')" = "$AUTHORIZATION_SHA"

CURRENT_STAGE=final_submission_preflight
test ! -e "$OUTPUT"
test ! -e "$PACKAGE"
EXISTING_JOB=$(squeue -h -n regge_rl_cal_004 -o '%A')
test -z "$EXISTING_JOB"

CURRENT_STAGE=record_single_submission_request
SUBMISSION_REQUEST=$SUBMISSION_RECEIPTS/formal_calibration_004-seq27.requested.json
SUBMISSION_STDOUT=$SUBMISSION_RECEIPTS/formal_calibration_004-seq27.stdout.txt
SUBMISSION_STDERR=$SUBMISSION_RECEIPTS/formal_calibration_004-seq27.stderr.txt
test ! -e "$SUBMISSION_STDOUT"
test ! -e "$SUBMISSION_STDERR"
"$RUNTIME/bin/python" -B - "$SUBMISSION_REQUEST" <<'PY'
from datetime import datetime, timezone
import json
from pathlib import Path
import sys

with Path(sys.argv[1]).open("x", encoding="utf-8") as target:
    json.dump({
        "schema": "regge_record_length_single_submission_request_v01",
        "formal_attempt": "20260929-004",
        "sequence": 27,
        "requested_utc": datetime.now(timezone.utc).isoformat(),
        "submission_count_authorized": 1,
        "automatic_retry": False,
    }, target, indent=2)
    target.write("\n")
PY

CURRENT_STAGE=submit
JOB_SUBMITTED=null
MANUAL_RECONCILIATION_REQUIRED=true
(
  set -o noclobber
  sbatch "$CAPSULE/hpc/regge_record_length_calibration_20260929_004.slurm" \
    > "$SUBMISSION_STDOUT" 2> "$SUBMISSION_STDERR"
)
CURRENT_STAGE=parse_unique_submission_id
SUBMITTED_JOB_ID=$("$RUNTIME/bin/python" -B - "$SUBMISSION_STDOUT" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
matches = re.findall(r"(?m)^Submitted batch job ([0-9]+)\s*$", text)
if len(matches) != 1:
    raise SystemExit("No unique scheduler submission identity; reconcile without retry")
print(matches[0])
PY
)
JOB_SUBMITTED=true

CURRENT_STAGE=write_submission_receipt
SUBMISSION_RECEIPT=$SUBMISSION_RECEIPTS/formal_calibration_004-$SUBMITTED_JOB_ID.json
"$RUNTIME/bin/python" -B - "$SUBMISSION_RECEIPT" "$SUBMITTED_JOB_ID" \
  "$ARCHIVE_SHA" "$MANIFEST_SHA" "$AUTHORIZATION_SHA" \
  "$SUBMISSION_REQUEST" "$SUBMISSION_STDOUT" "$SUBMISSION_STDERR" <<'PY'
from datetime import datetime, timezone
import json
from pathlib import Path
import sys

import hashlib

(target, job_id, archive_sha, manifest_sha, authorization_sha,
 request_path, stdout_path, stderr_path) = sys.argv[1:]
evidence = {
    Path(path).name: hashlib.sha256(Path(path).read_bytes()).hexdigest()
    for path in (request_path, stdout_path, stderr_path)
}
payload = {
    "schema": "regge_record_length_hpc_submission_receipt_v01",
    "status": "submitted",
    "slurm_job_id": job_id,
    "slurm_job_name": "regge_rl_cal_004",
    "formal_attempt": "20260929-004",
    "remote_output": "/data1/home/sunyiq/regge_record_length_20260929_001/formal_calibration_004",
    "archive_sha256": archive_sha,
    "capsule_manifest_sha256": manifest_sha,
    "authorization_sha256": authorization_sha,
    "job_submitted": True,
    "submission_evidence_sha256": evidence,
    "submission_count": 1,
    "manual_reconciliation_required": False,
    "retry_policy": "none",
    "submitted_utc": datetime.now(timezone.utc).isoformat(),
}
with Path(target).open("x", encoding="utf-8") as stream:
    json.dump(payload, stream, ensure_ascii=False, indent=2)
    stream.write("\n")
PY

CURRENT_STAGE=complete
MANUAL_RECONCILIATION_REQUIRED=false
trap - ERR
echo "FORMAL_JOB_ID=$SUBMITTED_JOB_ID"
cat "$SUBMISSION_RECEIPT" || true
squeue -j "$SUBMITTED_JOB_ID" -o '%.18i %.24j %.9P %.10T %.30R' || true
echo "FORMAL_SUBMISSION_COMPLETE"
