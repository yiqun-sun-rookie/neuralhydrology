#!/bin/bash
set -eo pipefail

sequence=39
ROOT=/data1/home/sunyiq/regge_record_length_20260929_001
CAPSULE=$ROOT/deploy/formal_calibration_capsule_005
SOURCE=$ROOT/formal_calibration_005
PACKAGE=$ROOT/transport_package_005
PYTHON=$ROOT/runtime_probe_005/bin/python
RECEIPTS=$ROOT/submission_receipts
REQUEST=$RECEIPTS/package_005-seq39.requested.json
STDOUT=$RECEIPTS/package_005-seq39.stdout.txt
STDERR=$RECEIPTS/package_005-seq39.stderr.txt
FAILURE=$RECEIPTS/package_005-seq39.failed.json
CURRENT_STAGE=preflight
JOB_SUBMITTED=false
SUBMITTED_JOB_ID=
MANUAL_RECONCILIATION_REQUIRED=false
export PYTHONDONTWRITEBYTECODE=1

on_error() {
  rc=$?
  trap - ERR
  if [ ! -e "$FAILURE" ]; then
    "$PYTHON" -B - "$FAILURE" "$CURRENT_STAGE" "$rc" "$JOB_SUBMITTED" "$SUBMITTED_JOB_ID" "$MANUAL_RECONCILIATION_REQUIRED" <<'PYFAIL'
from datetime import datetime, timezone
import json
from pathlib import Path
import sys
path, stage, rc, submitted, job_id, reconcile = sys.argv[1:]
payload = dict(schema="regge_record_length_package_submission_failure_v01",
 formal_attempt="20260930-005", sequence=39, status="failed", passed=False,
 stage=stage, exit_code=int(rc), job_submitted=json.loads(submitted),
 submitted_job_id=job_id or None, manual_reconciliation_required=json.loads(reconcile),
 automatic_retry=False, failed_utc=datetime.now(timezone.utc).isoformat())
with Path(path).open("x", encoding="utf-8") as stream:
    json.dump(payload, stream, indent=2)
    stream.write(chr(10))
PYFAIL
  fi
  exit "$rc"
}
trap on_error ERR

test -x "$PYTHON"
test -d "$RECEIPTS"
test ! -e "$FAILURE"
test ! -e "$REQUEST"
test ! -e "$STDOUT"
test ! -e "$STDERR"
test ! -e "$PACKAGE"
test -f "$ROOT/transport_credentials_005/upload_token_private.pem"
test "$(stat -c '%a' "$ROOT/transport_credentials_005/upload_token_private.pem")" = "600"
EXISTING=$(squeue -h -n regge_rl_pack_005 -o '%A')
test -z "$EXISTING"

"$PYTHON" -B - "$ROOT" "$CAPSULE" "$SOURCE" "$PACKAGE" "$RECEIPTS" <<'PYPRE'
import hashlib
import json
from pathlib import Path
import subprocess
import sys
root, capsule, source, package, receipts = map(Path, sys.argv[1:])
def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
expected = ["RL-E1-M06", "RL-E1-M12", "RL-E2-M06", "RL-E2-M12", "RL-E3-M06", "RL-E3-M12"]
manifest_sha = "314724ad9d6d1c107670dbd654a4fd244d4496e7eafd2d1f6cb3b2d4e1ae5122"
authorization_sha = "1863cff71e04a8d6b9b90216528bce6482d88d33aaec4c7e1cc56e955aaad14a"
batch_manifest_sha = "0e43a502924796942e5e94bff8532b512bf72e13ee0db42155cd690d46f3d8d6"
assert not package.exists(), "package already exists"
assert not list(receipts.glob("package_005-*.json")), "earlier package request/receipt exists"
assert not list((root / "wrapper_receipts").glob("package_005-*.failed.json")), "earlier package failure exists"
assert not (source / "batch_failed.json").exists()
assert digest(capsule / "capsule_manifest.json") == manifest_sha
assert digest(capsule / "calibration_authorization.json") == authorization_sha
assert digest(capsule / "hpc/regge_record_length_package_20260930_005.slurm") == "8b6830d23a2dfd93cfa0a6e0d09f9f44d5aa61ad38ae16372cbf74647559dd2e"
assert digest(capsule / "hpc_signing_public_key.pem") == "c61674eebd71b54ca41add7face1eef170e85760cd55b56bf21f1b13bdfd0205"
assert digest(capsule / "output_recipient_certificate.pem") == "8c7827ef41c50761b927da1f750f1813685acdf393df326dfee55c906ff3d4c4"
batch = json.loads((source / "batch_receipt.json").read_text(encoding="utf-8"))
assert batch["status"] == "complete" and batch["passed"] is True
assert batch["expected_experiments"] == expected and batch["started_experiments"] == expected
assert [row["exp_id"] for row in batch["completed"]] == expected
assert all(row["returncode"] == 0 and row["receipt_status"] == "complete" for row in batch["completed"])
assert len(batch["attempts"]) == 6 and all(row["status"] == "complete" and row["returncode"] == 0 for row in batch["attempts"])
assert batch["environment"]["slurm_job_id"] == "233416"
assert batch["capsule_manifest_sha256"] == manifest_sha and batch["authorization_sha256"] == authorization_sha
assert batch["manifest_sha256"] == batch_manifest_sha == digest(source / "batch_manifest.json")
assert batch["batch_started_sha256"] == digest(source / "batch_started.json")
accounting = subprocess.run(["sacct", "-n", "-P", "-j", "233416", "--format=JobIDRaw,JobName,State,ExitCode"], capture_output=True, text=True, check=True)
rows = [line.split("|") for line in accounting.stdout.splitlines() if line.strip()]
main = [row for row in rows if row[0] == "233416"]
assert len(main) == 1 and main[0][1:4] == ["regge_rl_cal_005", "COMPLETED", "0:0"], accounting.stdout
assert any(row[0] == "233416.batch" and row[2:4] == ["COMPLETED", "0:0"] for row in rows), accounting.stdout
print("PACKAGE_TERMINAL_AND_IDENTITY_PREFLIGHT=PASS")
print(accounting.stdout, end="")
PYPRE

CURRENT_STAGE=write_single_package_request
"$PYTHON" -B - "$REQUEST" <<'PYREQ'
from datetime import datetime, timezone
import json
from pathlib import Path
import sys
with Path(sys.argv[1]).open("x", encoding="utf-8") as stream:
    json.dump(dict(schema="regge_record_length_package_single_submission_request_v01",
     formal_attempt="20260930-005", sequence=39, requested_utc=datetime.now(timezone.utc).isoformat(),
     calibration_job_id="233416", package_job_name="regge_rl_pack_005",
     submission_count_authorized=1, automatic_retry=False), stream, indent=2)
    stream.write(chr(10))
PYREQ

CURRENT_STAGE=submit
JOB_SUBMITTED=null
MANUAL_RECONCILIATION_REQUIRED=true
(
  set -o noclobber
  sbatch "$CAPSULE/hpc/regge_record_length_package_20260930_005.slurm" > "$STDOUT" 2> "$STDERR"
)
CURRENT_STAGE=parse_unique_job_id
SUBMITTED_JOB_ID=$("$PYTHON" -B - "$STDOUT" <<'PYID'
from pathlib import Path
import re
import sys
content = Path(sys.argv[1]).read_text(encoding="utf-8")
matches = re.findall(r"(?m)^Submitted batch job ([0-9]+) *$", content)
if len(matches) != 1:
    raise SystemExit("Package submission ambiguous; reconcile exact request without retry")
print(matches[0])
PYID
)
JOB_SUBMITTED=true
CURRENT_STAGE=write_submission_receipt
"$PYTHON" -B - "$RECEIPTS/package_005-$SUBMITTED_JOB_ID.json" "$SUBMITTED_JOB_ID" "$REQUEST" "$STDOUT" "$STDERR" <<'PYREC'
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import sys
target, job_id, request, stdout, stderr = sys.argv[1:]
payload = dict(schema="regge_record_length_package_submission_receipt_v01",
 status="submitted", formal_attempt="20260930-005", sequence=39,
 calibration_job_id="233416", slurm_job_id=job_id, slurm_job_name="regge_rl_pack_005",
 submission_count=1, automatic_retry=False, manual_reconciliation_required=False,
 source_root="/data1/home/sunyiq/regge_record_length_20260929_001/formal_calibration_005",
 package_root="/data1/home/sunyiq/regge_record_length_20260929_001/transport_package_005",
 submitted_utc=datetime.now(timezone.utc).isoformat(),
 evidence_sha256={Path(p).name:hashlib.sha256(Path(p).read_bytes()).hexdigest() for p in (request, stdout, stderr)})
with Path(target).open("x", encoding="utf-8") as stream:
    json.dump(payload, stream, indent=2)
    stream.write(chr(10))
print("PACKAGE_SUBMISSION_RECEIPT_BEGIN")
print(json.dumps(payload, separators=(",", ":")))
print("PACKAGE_SUBMISSION_RECEIPT_END")
PYREC
CURRENT_STAGE=complete
MANUAL_RECONCILIATION_REQUIRED=false
trap - ERR
squeue -j "$SUBMITTED_JOB_ID" -o '%.18i %.24j %.9P %.10T %.30R' || true
echo PACKAGE_SINGLE_SUBMISSION_COMPLETE
