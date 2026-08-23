#!/usr/bin/env bash
set -eo pipefail

TARGET=/data1/home/sunyiq/kalmannet_tukf19_20260823_retry2
PREVIOUS_TARGET=/data1/home/sunyiq/kalmannet_tukf19_20260823_retry1
PREVIOUS_REPORT="$PREVIOUS_TARGET/artifacts/tukf19_hpc_deployment_retry1_v1/smoke/smoke_report.json"
PREVIOUS_FORMAL_SUBMISSION="$PREVIOUS_TARGET/artifacts/tukf19_hpc_deployment_retry1_v1/status/formal_submission.json"
MAILBOX=/data1/home/sunyiq/hpc_mailbox
PAYLOAD_DIR="$MAILBOX/payload/kalmannet-tukf19"
ARCHIVE_NAME=tukf19_hpc_payload_retry2_v1.tar.gz
SOURCE_MANIFEST_NAME=bundle_manifest_retry2.sha256.json
TARGET_MANIFEST_NAME=bundle_manifest.sha256.json
SOURCE_ARCHIVE="$PAYLOAD_DIR/$ARCHIVE_NAME"
SOURCE_MANIFEST="$PAYLOAD_DIR/$SOURCE_MANIFEST_NAME"
EXPECTED_ARCHIVE_SHA=3d1b118be805a95746fb8c7ac999df627675bb18573fb66311f8572395a7f629
EXPECTED_ARCHIVE_BYTES=257768
EXPECTED_MANIFEST_SHA=cc5eb8cd0835559bf8dc4d2289c5ae6399534980a0925957a31ce362527a0bc9
EXPECTED_PREVIOUS_REPORT_SHA=7ab176aa0fa4a569a113575952d4334d79e977b55440692d70c8ea583038ab72
STAGING=""

test "$(sha256sum "$PREVIOUS_REPORT" | awk '{print $1}')" = "$EXPECTED_PREVIOUS_REPORT_SHA"
test ! -e "$PREVIOUS_FORMAL_SUBMISSION"

source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
PYTHON=$(command -v python)
test -n "$PYTHON"

verify_transport() {
  archive=$1
  manifest=$2
  test -f "$archive" -a -f "$manifest"
  test "$(wc -c < "$archive")" = "$EXPECTED_ARCHIVE_BYTES"
  test "$(sha256sum "$archive" | awk '{print $1}')" = "$EXPECTED_ARCHIVE_SHA"
  test "$(sha256sum "$manifest" | awk '{print $1}')" = "$EXPECTED_MANIFEST_SHA"
}

verify_extracted() {
  root=$1
  "$PYTHON" -B - "$root" <<'PY'
import hashlib
import json
from pathlib import Path, PurePosixPath
import sys

root = Path(sys.argv[1]).resolve()
external = json.loads((root / "_transport/bundle_manifest.sha256.json").read_text(encoding="utf-8"))
payload_path = root / external["payload_manifest_name"]
payload_bytes = payload_path.read_bytes()
assert hashlib.sha256(payload_bytes).hexdigest() == external["payload_manifest_sha256"]
payload = json.loads(payload_bytes.decode("utf-8"))
assert payload["deployment_id"] == external["deployment_id"]
assert payload["members"] == external["members"]
for name, expected in payload["members"].items():
    pure = PurePosixPath(name)
    assert not pure.is_absolute() and ".." not in pure.parts
    path = root.joinpath(*pure.parts).resolve()
    path.relative_to(root)
    assert path.is_file(), name
    assert hashlib.sha256(path.read_bytes()).hexdigest() == expected, name
print(f"PAYLOAD_MEMBERS_VERIFIED={len(payload['members'])}")
PY
}

cleanup_staging() {
  if [[ -n "$STAGING" && -d "$STAGING" ]]; then
    rm -rf -- "$STAGING"
  fi
}
trap cleanup_staging EXIT

if [[ -e "$TARGET" ]]; then
  test -d "$TARGET"
  verify_transport "$TARGET/_transport/$ARCHIVE_NAME" "$TARGET/_transport/$TARGET_MANIFEST_NAME"
  verify_extracted "$TARGET"
  echo "TUKF19_RETRY2_EXACT_DEPLOYMENT_ALREADY_PRESENT=$TARGET"
else
  STAGING=$(mktemp -d /data1/home/sunyiq/.kalmannet_tukf19_retry2_staging.XXXXXX)
  mkdir -p "$STAGING/_transport"
  cp "$SOURCE_ARCHIVE" "$STAGING/_transport/$ARCHIVE_NAME"
  cp "$SOURCE_MANIFEST" "$STAGING/_transport/$TARGET_MANIFEST_NAME"
  verify_transport "$STAGING/_transport/$ARCHIVE_NAME" "$STAGING/_transport/$TARGET_MANIFEST_NAME"
  tar -xzf "$STAGING/_transport/$ARCHIVE_NAME" -C "$STAGING"
  verify_extracted "$STAGING"
  sed -i 's/\r$//' "$STAGING"/hpc/tukf19_hbv_rolling_origin_formal_execution/*.slurm
  verify_extracted "$STAGING"
  mkdir -p "$STAGING/logs"
  mv "$STAGING" "$TARGET"
  STAGING=""
  echo "TUKF19_RETRY2_DEPLOYED=$TARGET"
fi

STATUS_ROOT="$TARGET/artifacts/tukf19_hpc_deployment_retry2_v1/status"
SMOKE_SUBMISSION="$STATUS_ROOT/smoke_submission.json"
FORMAL_SUBMISSION="$STATUS_ROOT/formal_submission.json"
SMOKE_REPORT="$TARGET/artifacts/tukf19_hpc_deployment_retry2_v1/smoke/smoke_report.json"
mkdir -p "$STATUS_ROOT"

read_job_id() {
  "$PYTHON" -B - "$1" <<'PY'
import json
from pathlib import Path
import sys
print(int(json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["job_id"]))
PY
}

write_submission() {
  destination=$1
  kind=$2
  job_id=$3
  submit_output=$4
  "$PYTHON" -B - "$destination" "$kind" "$job_id" "$submit_output" "$EXPECTED_ARCHIVE_SHA" <<'PY'
from datetime import datetime, timezone
import json
from pathlib import Path
import sys

path = Path(sys.argv[1])
payload = {
    "schema_version": f"tukf19_hpc_{sys.argv[2]}_submission_v1",
    "job_kind": sys.argv[2],
    "job_id": int(sys.argv[3]),
    "submission_output": sys.argv[4],
    "bundle_sha256": sys.argv[5],
    "submitted_at_utc": datetime.now(timezone.utc).isoformat(),
}
with path.open("x", encoding="utf-8", newline="\n") as handle:
    json.dump(payload, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
}

if [[ -f "$SMOKE_SUBMISSION" ]]; then
  SMOKE_JOB_ID=$(read_job_id "$SMOKE_SUBMISSION")
else
  SMOKE_OUTPUT_FILE="$STATUS_ROOT/smoke_sbatch_output.txt"
  test ! -e "$SMOKE_OUTPUT_FILE"
  set +e
  SMOKE_OUTPUT=$(sbatch "$TARGET/hpc/tukf19_hbv_rolling_origin_formal_execution/submit_smoke_cpu_retry2.slurm" 2>&1)
  SMOKE_RC=$?
  set -e
  printf '%s\n' "$SMOKE_OUTPUT" | tee "$SMOKE_OUTPUT_FILE"
  test "$SMOKE_RC" -eq 0
  SMOKE_JOB_ID=$(printf '%s\n' "$SMOKE_OUTPUT" | awk '/^Submitted batch job [0-9]+$/ {print $4}')
  test -n "$SMOKE_JOB_ID"
  write_submission "$SMOKE_SUBMISSION" smoke "$SMOKE_JOB_ID" "$SMOKE_OUTPUT"
fi
echo "TUKF19_RETRY2_SMOKE_JOB_ID=$SMOKE_JOB_ID"

SMOKE_COMPLETE=0
for attempt in $(seq 1 80); do
  accounting=$(sacct -j "$SMOKE_JOB_ID" -X -n -P --format=JobIDRaw,State,ExitCode 2>/dev/null | awk -F'|' -v id="$SMOKE_JOB_ID" '$1 == id {print $2 "|" $3; exit}')
  state=$(printf '%s' "$accounting" | awk -F'|' '{print $1}' | sed 's/+.*$//')
  exit_code=$(printf '%s' "$accounting" | awk -F'|' '{print $2}')
  if [[ "$state" = "COMPLETED" && "$exit_code" = "0:0" ]]; then
    SMOKE_COMPLETE=1
    break
  fi
  case "$state" in
    FAILED|CANCELLED|TIMEOUT|NODE_FAIL|OUT_OF_MEMORY|PREEMPTED|BOOT_FAIL|DEADLINE)
      echo "TUKF19_RETRY2_SMOKE_TERMINAL_FAILURE state=$state exit_code=$exit_code" >&2
      exit 173
      ;;
  esac
  echo "TUKF19_RETRY2_SMOKE_WAIT attempt=$attempt state=${state:-UNKNOWN} exit_code=${exit_code:-UNKNOWN}"
  sleep 30
done
test "$SMOKE_COMPLETE" -eq 1
test -f "$SMOKE_REPORT"
"$PYTHON" -B - "$SMOKE_REPORT" "$EXPECTED_ARCHIVE_SHA" <<'PY'
import json
from pathlib import Path
import sys

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assert report["status"] == "HPC_SMOKE_PASS", report.get("status")
assert report["bundle_sha256"] == sys.argv[2]
assert report["checks"] and all(report["checks"].values()), report["checks"]
print("TUKF19_RETRY2_BOUND_SMOKE_PASS")
PY

if [[ -f "$FORMAL_SUBMISSION" ]]; then
  FORMAL_JOB_ID=$(read_job_id "$FORMAL_SUBMISSION")
else
  FORMAL_OUTPUT_FILE="$STATUS_ROOT/formal_sbatch_output.txt"
  test ! -e "$FORMAL_OUTPUT_FILE"
  set +e
  FORMAL_OUTPUT=$(sbatch "$TARGET/hpc/tukf19_hbv_rolling_origin_formal_execution/submit_formal_cpu_retry2.slurm" 2>&1)
  FORMAL_RC=$?
  set -e
  printf '%s\n' "$FORMAL_OUTPUT" | tee "$FORMAL_OUTPUT_FILE"
  test "$FORMAL_RC" -eq 0
  FORMAL_JOB_ID=$(printf '%s\n' "$FORMAL_OUTPUT" | awk '/^Submitted batch job [0-9]+$/ {print $4}')
  test -n "$FORMAL_JOB_ID"
  write_submission "$FORMAL_SUBMISSION" formal "$FORMAL_JOB_ID" "$FORMAL_OUTPUT"
fi
echo "TUKF19_RETRY2_FORMAL_JOB_ID=$FORMAL_JOB_ID"
squeue -j "$FORMAL_JOB_ID" -o '%.18i|%.12P|%.30j|%.10T|%.10M|%.10l|%R' 2>&1 || true
echo TUKF19_RETRY2_SMOKE_PASSED_AND_FORMAL_SUBMITTED
