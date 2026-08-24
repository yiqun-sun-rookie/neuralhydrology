#!/usr/bin/env bash
set -eo pipefail

TARGET=/data1/home/sunyiq/kalmannet_tukf20_20260824
STATUS_ROOT="$TARGET/artifacts/tukf20_hpc_deployment_v1/status"
SMOKE_REPORT="$TARGET/artifacts/tukf20_hpc_deployment_v1/smoke/smoke_report.json"
RAW="$STATUS_ROOT/smoke_submission_raw.txt"
RECEIPT="$STATUS_ROOT/smoke_submission_receipt.json"
JOBID_FILE="$STATUS_ROOT/smoke_job_id.txt"
SQUEUE_EVIDENCE="$STATUS_ROOT/smoke_squeue_snapshot.txt"
SACCT_EVIDENCE="$STATUS_ROOT/smoke_sacct_snapshot.txt"
COMPLETION="$STATUS_ROOT/smoke_completion.json"
EXPECTED_JID=210745
EXPECTED_ARCHIVE_SHA=721fa666319cc448e901515d066bb217560c87ec8edd19e5cbb2300269074f76
EXPECTED_CONFIG_SHA=56ea39cad0debfd996f86d221d0de3671c8ecdfbac99e9b9bb96a913c7ec614f
DEPLOYMENT_ID=TUKF20_HBV_ROLLING_ORIGIN_JOINT_LEARNING_HPC_DEPLOYMENT_V1
SCIENTIFIC_ID=TUKF20_HBV_ROLLING_ORIGIN_JOINT_LEARNING_V1

source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
PYTHON=$(command -v python)
test -n "$PYTHON"
test -d "$TARGET" -a -d "$STATUS_ROOT/.smoke_submission_claim"
for path in "$RAW" "$RECEIPT" "$JOBID_FILE" "$SQUEUE_EVIDENCE"; do
  test -s "$path"
done
JID=$(tr -d '[:space:]' < "$JOBID_FILE")
test "$JID" = "$EXPECTED_JID"

echo '=== TUKF20 SMOKE SUBMISSION EVIDENCE ==='
"$PYTHON" -B - "$RAW" "$RECEIPT" "$SQUEUE_EVIDENCE" "$JID" "$EXPECTED_ARCHIVE_SHA" "$EXPECTED_CONFIG_SHA" "$DEPLOYMENT_ID" "$SCIENTIFIC_ID" <<'PY'
import hashlib
import json
from pathlib import Path
import re
import sys

raw_path, receipt_path, queue_path = map(Path, sys.argv[1:4])
job_id = int(sys.argv[4])
raw = raw_path.read_text(encoding="utf-8")
receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
matches = re.findall(r"(?:^|\n)Submitted batch job ([0-9]+)(?:\n|$)", raw)
assert matches == [str(job_id)]
assert receipt["schema_version"] == "tukf20_hpc_submission_receipt_v1"
assert receipt["deployment_id"] == sys.argv[7]
assert receipt["scientific_experiment_id"] == sys.argv[8]
assert receipt["stage"] == "smoke"
assert int(receipt["job_id"]) == job_id
assert receipt["bundle_sha256"] == sys.argv[5]
assert receipt["deployment_config_sha256"] == sys.argv[6]
assert receipt["raw_output_sha256"] == hashlib.sha256(raw_path.read_bytes()).hexdigest()
assert receipt["squeue_snapshot_sha256"] == hashlib.sha256(queue_path.read_bytes()).hexdigest()
queue_ids = [line.split("|", 1)[0] for line in queue_path.read_text(encoding="utf-8").splitlines()]
assert queue_ids.count(str(job_id)) == 1
print("TUKF20_SMOKE_SUBMISSION_EVIDENCE_VERIFIED")
PY

echo '=== TUKF20 SMOKE LIVE STATUS ==='
squeue --jobs "$JID" --format='%.18i|%.12P|%.30j|%.10T|%.10M|%.10l|%R' 2>&1 || true
SACCT_CURRENT=$(sacct -X --noheader --parsable2 --jobs "$JID" \
  --format=JobID,JobName,Partition,AllocCPUS,State,ExitCode,Elapsed,Start,End 2>/dev/null || true)
printf '%s\n' "$SACCT_CURRENT"
MAIN_ROW=$(printf '%s\n' "$SACCT_CURRENT" | awk -F'|' -v id="$JID" '$1 == id {print; exit}')
STATE=$(printf '%s' "$MAIN_ROW" | awk -F'|' '{print $5}' | sed 's/+.*$//')
EXIT_CODE=$(printf '%s' "$MAIN_ROW" | awk -F'|' '{print $6}')

echo '=== TUKF20 SMOKE LOG TAIL ==='
tail -n 100 "$TARGET/logs/smoke-${JID}.out" 2>/dev/null || true
tail -n 100 "$TARGET/logs/smoke-${JID}.err" 2>/dev/null || true

if [[ "$STATE" = "COMPLETED" && "$EXIT_CODE" = "0:0" ]]; then
  SACCT_TMP="$SACCT_EVIDENCE.tmp.$$"
  printf '%s\n' "$SACCT_CURRENT" > "$SACCT_TMP"
  if [[ -e "$SACCT_EVIDENCE" ]]; then
    cmp -s "$SACCT_TMP" "$SACCT_EVIDENCE"
    rm -f -- "$SACCT_TMP"
  else
    mv "$SACCT_TMP" "$SACCT_EVIDENCE"
  fi
  test -s "$SMOKE_REPORT"
  "$PYTHON" -B - "$COMPLETION" "$SMOKE_REPORT" "$SACCT_EVIDENCE" "$JID" "$EXPECTED_ARCHIVE_SHA" "$EXPECTED_CONFIG_SHA" "$DEPLOYMENT_ID" "$SCIENTIFIC_ID" <<'PY'
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import sys

destination, report_path, sacct_path = map(Path, sys.argv[1:4])
job_id = int(sys.argv[4])
report = json.loads(report_path.read_text(encoding="utf-8"))
assert report["schema_version"] == "tukf20_hpc_smoke_report_v1"
assert report["deployment_id"] == sys.argv[7]
assert report["scientific_experiment_id"] == sys.argv[8]
assert report["status"] == "HPC_SMOKE_PASS"
assert isinstance(report.get("checks"), dict) and report["checks"]
assert all(bool(value) for value in report["checks"].values())
assert int(report["slurm_job_id"]) == job_id
assert report["bundle_sha256"] == sys.argv[5]
assert report["deployment_config_sha256"] == sys.argv[6]
rows = [line.rstrip("|").split("|") for line in sacct_path.read_text(encoding="utf-8").splitlines()]
main = [row for row in rows if len(row) >= 6 and row[0] == str(job_id)]
assert len(main) == 1
assert main[0][2:6] == ["hcpu48y", "1", "COMPLETED", "0:0"]
fixed = {
    "schema_version": "tukf20_hpc_smoke_completion_v1",
    "deployment_id": sys.argv[7],
    "scientific_experiment_id": sys.argv[8],
    "bundle_sha256": sys.argv[5],
    "deployment_config_sha256": sys.argv[6],
    "smoke_report_sha256": hashlib.sha256(report_path.read_bytes()).hexdigest(),
    "smoke_job_id": job_id,
    "slurm_state": "COMPLETED",
    "slurm_exit_code": "0:0",
    "status": "HPC_SMOKE_SLURM_COMPLETED",
    "sacct_snapshot_sha256": hashlib.sha256(sacct_path.read_bytes()).hexdigest(),
}
if destination.exists():
    existing = json.loads(destination.read_text(encoding="utf-8"))
    assert all(existing.get(key) == value for key, value in fixed.items())
else:
    payload = {**fixed, "recorded_at_utc": datetime.now(timezone.utc).isoformat()}
    with destination.open("x", encoding="utf-8", newline="\n") as handle:
        json.dump(payload, handle, indent=2, sort_keys=True)
        handle.write("\n")
print(json.dumps({"job_id": job_id, "status": fixed["status"], "smoke_checks": len(report["checks"])}, sort_keys=True))
PY
  echo TUKF20_SMOKE_GATE_FULLY_COMPLETED
  exit 0
fi

case "$STATE" in
  FAILED|CANCELLED|TIMEOUT|NODE_FAIL|OUT_OF_MEMORY|PREEMPTED|BOOT_FAIL|DEADLINE)
    FAILURE_SACCT="$STATUS_ROOT/smoke_terminal_failure_sacct_${JID}.txt"
    if [[ ! -e "$FAILURE_SACCT" ]]; then
      printf '%s\n' "$SACCT_CURRENT" > "$FAILURE_SACCT"
    fi
    echo "TUKF20_SMOKE_TERMINAL_FAILURE state=$STATE exit_code=$EXIT_CODE"
    exit 80
    ;;
esac

echo "TUKF20_SMOKE_NOT_TERMINAL state=${STATE:-UNKNOWN} exit_code=${EXIT_CODE:-UNKNOWN}"
exit 0
