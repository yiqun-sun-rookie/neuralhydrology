#!/usr/bin/env bash
exec bash /data1/home/sunyiq/hpc_mailbox/inbox/kalmannet-daily-camels/seq46_a37_probe215178_gpu_partition_audit.sh

set -Eeuo pipefail
umask 077

EXPECTED_USER="sunyiq"
MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
PAYLOAD_DIRECTORY="${MAILBOX_ROOT}/payload/kalmannet-daily-camels/native-full-state-a20-contract-a34-infra-retry2-v25"
ARCHIVE="${PAYLOAD_DIRECTORY}/DAILY_CAMELS_NATIVE_KALMANNET_FULL_STATE_MASKED_NSE_SMOKE_V1_20260825_A34.tar.gz"
OUTER_MANIFEST="${PAYLOAD_DIRECTORY}/bundle_manifest.sha256.json"
ARCHIVE_SHA256="1b70cd8f6dd3eb09e41c09f97848f4364a53470366f7189d363401ab0ad74b22"
ARCHIVE_SIZE=245237
EXPERIMENT_ID="DAILY_CAMELS_NATIVE_KALMANNET_FULL_STATE_MASKED_NSE_SMOKE_V1_20260825_A34"
EXECUTION_ATTEMPT_ID="DAILY_CAMELS_NATIVE_KALMANNET_FULL_STATE_A34_INFRA_RETRY2_SEQ25"
RUN_BASE="/data1/home/sunyiq/kalmannet_daily_camels_full_state_a34_retry2_20260825"
SOURCE_DIRECTORY="${RUN_BASE}/source_A34_infra_retry2_seq25"
RUN_DIRECTORY="${RUN_BASE}/runs/${EXPERIMENT_ID}"
STATUS_DIRECTORY="${RUN_BASE}/status"
STAGING_DIRECTORY="/data1/home/sunyiq/kalmannet_daily_camels_full_state_a34_retry2_staging_20260825"
OUTBOX_DIRECTORY="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels"
EVIDENCE_ARCHIVE="${OUTBOX_DIRECTORY}/DAILY_CAMELS_NATIVE_KALMANNET_FULL_STATE_A34_INFRA_RETRY2_SEQ25_evidence.tar.gz"
NAMESPACE_OWNED=0
SAFE_TO_PACKAGE=0
FINAL_STATUS="SEQ25_A34_INFRA_RETRY2_STARTED"
TRAINING_JOB_ID="NOT_SUBMITTED"

sha256_file() { sha256sum "$1" | awk '{print $1}'; }

package_evidence() {
  local command_exit_code="$1" temporary_archive
  if [[ "$NAMESPACE_OWNED" -ne 1 ]]; then
    printf 'evidence_archive=NOT_CREATED status=%s exit_code=%s\n' "$FINAL_STATUS" "$command_exit_code"
    return 0
  fi
  if [[ "$SAFE_TO_PACKAGE" -ne 1 ]]; then
    printf 'evidence_archive=NOT_CREATED active_job_not_terminal=1 status=%s exit_code=%s training_job_id=%s\n' \
      "$FINAL_STATUS" "$command_exit_code" "$TRAINING_JOB_ID"
    return 0
  fi
  printf '%s\n' "$FINAL_STATUS" > "${STATUS_DIRECTORY}/final_status.txt" || return 91
  printf '%s\n' "$command_exit_code" > "${STATUS_DIRECTORY}/command_exit_code.txt" || return 92
  printf '%s\n' "$TRAINING_JOB_ID" > "${STATUS_DIRECTORY}/training_job_id.txt" || return 93
  date -u +%Y-%m-%dT%H:%M:%SZ > "${STATUS_DIRECTORY}/finished_time_utc.txt" || return 94
  if find "$RUN_BASE" -type l -print -quit | grep -q .; then return 95; fi
  mkdir -p "$OUTBOX_DIRECTORY" || return 96
  temporary_archive="$(mktemp "${STAGING_DIRECTORY}/evidence.XXXXXX.tar.gz")" || return 97
  tar -czf "$temporary_archive" -C "$(dirname "$RUN_BASE")" "$(basename "$RUN_BASE")" || return 98
  [[ -s "$temporary_archive" ]] && gzip -t "$temporary_archive" || return 99
  [[ ! -e "$EVIDENCE_ARCHIVE" && ! -L "$EVIDENCE_ARCHIVE" ]] || return 100
  ln -- "$temporary_archive" "$EVIDENCE_ARCHIVE" || return 101
  printf 'evidence_archive=%s\n' "$EVIDENCE_ARCHIVE"
  printf 'evidence_archive_sha256=%s\n' "$(sha256_file "$EVIDENCE_ARCHIVE")"
  printf 'evidence_archive_size=%s\n' "$(stat -c '%s' "$EVIDENCE_ARCHIVE")"
  printf 'evidence_status=%s command_exit_code=%s training_job_id=%s\n' "$FINAL_STATUS" "$command_exit_code" "$TRAINING_JOB_ID"
  rm -- "$temporary_archive" || return 102
}

on_exit() {
  local main_exit_code="$?" package_exit_code=0
  trap - EXIT INT TERM
  set +e
  package_evidence "$main_exit_code"
  package_exit_code="$?"
  if [[ "$main_exit_code" -eq 0 && "$package_exit_code" -ne 0 ]]; then exit 90; fi
  exit "$main_exit_code"
}

ACTUAL_USER="$(id -un)"
ACTUAL_UID="$(id -u)"
EXPECTED_UID="$(id -u "$EXPECTED_USER")"
if [[ "${USER-}" != "$EXPECTED_USER" || "$ACTUAL_USER" != "$EXPECTED_USER" || "$ACTUAL_UID" != "$EXPECTED_UID" ]]; then
  echo "fixed-user check failed" >&2
  exit 50
fi
[[ -f "$ARCHIVE" && ! -L "$ARCHIVE" ]] || { echo "A34 archive absent or symbolic" >&2; exit 51; }
[[ -f "$OUTER_MANIFEST" && ! -L "$OUTER_MANIFEST" ]] || { echo "A34 outer manifest absent or symbolic" >&2; exit 52; }
[[ "$(stat -c '%s' "$ARCHIVE")" = "$ARCHIVE_SIZE" ]] || { echo "A34 archive size differs" >&2; exit 53; }
[[ "$(sha256_file "$ARCHIVE")" = "$ARCHIVE_SHA256" ]] || { echo "A34 archive hash differs" >&2; exit 54; }
python - "$OUTER_MANIFEST" "$EXPERIMENT_ID" "$ARCHIVE_SHA256" "$ARCHIVE_SIZE" <<'PY'
import json
from pathlib import Path
import sys

manifest = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if (
    manifest.get("schema_version")
    != "daily_camels_native_full_state_outer_bundle_manifest_v1"
    or manifest.get("experiment_id") != sys.argv[2]
    or manifest.get("archive_sha256") != sys.argv[3]
    or int(manifest.get("archive_size_bytes", -1)) != int(sys.argv[4])
    or int(manifest.get("file_count", -1)) != 34
    or manifest.get("daily_only") is not True
    or manifest.get("formal_evaluation_enabled") is not False
):
    raise SystemExit("A34 outer manifest identity differs")
PY
for path in "$RUN_BASE" "$STAGING_DIRECTORY" "$EVIDENCE_ARCHIVE"; do
  [[ ! -e "$path" && ! -L "$path" ]] || { echo "isolated A34 path already exists: $path" >&2; exit 55; }
done

mkdir "$RUN_BASE" "$STAGING_DIRECTORY"
mkdir "$SOURCE_DIRECTORY" "$STATUS_DIRECTORY" "$RUN_BASE/logs"
NAMESPACE_OWNED=1
SAFE_TO_PACKAGE=1
trap on_exit EXIT
trap 'FINAL_STATUS="SEQ25_A34_INFRA_RETRY2_INTERRUPTED"; exit 143' INT TERM
date -u +%Y-%m-%dT%H:%M:%SZ > "${STATUS_DIRECTORY}/started_time_utc.txt"
{
  printf 'archive=%s\n' "$ARCHIVE"
  printf 'archive_sha256=%s\n' "$ARCHIVE_SHA256"
  printf 'archive_size_bytes=%s\n' "$ARCHIVE_SIZE"
  printf 'outer_manifest=%s\n' "$OUTER_MANIFEST"
  printf 'outer_manifest_sha256=%s\n' "$(sha256_file "$OUTER_MANIFEST")"
} > "${STATUS_DIRECTORY}/payload_archive_identity.txt"
FINAL_STATUS="SEQ25_A34_INFRA_RETRY2_NAMESPACE_OWNED"
tar -xzf "$ARCHIVE" -C "$SOURCE_DIRECTORY"
set +u
source "/data1/home/${USER}/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
export PYTHONPATH="${SOURCE_DIRECTORY}/src:${SOURCE_DIRECTORY}"
cd "$SOURCE_DIRECTORY"
python - "$SOURCE_DIRECTORY" > "${STATUS_DIRECTORY}/offline-bundle-verification.json" <<'PY'
import json
from pathlib import Path
import sys

from hpc.daily_camels_native_kalmannet_full_state_masked_nse.preflight import verify_bundle

manifest = verify_bundle(Path(sys.argv[1]))
print(json.dumps({
    "status": "OFFLINE_BUNDLE_VERIFIED",
    "experiment_id": manifest["experiment_id"],
    "file_count": manifest["file_count"],
    "daily_only": manifest["daily_only"],
    "formal_evaluation_enabled": manifest["formal_evaluation_enabled"],
}, sort_keys=True, separators=(",", ":")))
PY
FINAL_STATUS="SEQ25_A34_INFRA_RETRY2_OFFLINE_BUNDLE_VERIFIED"

SAFE_TO_PACKAGE=0
if ! TRAINING_JOB_ID="$(sbatch --parsable hpc/daily_camels_native_kalmannet_full_state_masked_nse/submit_smoke_gpu.slurm)"; then
  SAFE_TO_PACKAGE=1
  FINAL_STATUS="SEQ25_A34_INFRA_RETRY2_SUBMISSION_REJECTED_HARD_STOP"
  exit 56
fi
[[ "$TRAINING_JOB_ID" =~ ^[0-9]+$ ]] || { FINAL_STATUS="SEQ25_A34_INFRA_RETRY2_SUBMISSION_IDENTITY_HARD_STOP"; exit 57; }
printf '%s\n' "$TRAINING_JOB_ID" > "${STATUS_DIRECTORY}/training_job_id.txt"
FINAL_STATUS="SEQ25_A34_INFRA_RETRY2_SUBMITTED"

TERMINAL_STATE=""
for attempt in $(seq 1 660); do
  TERMINAL_STATE="$(sacct -n -X -j "$TRAINING_JOB_ID" --format=State -P 2>/dev/null | awk -F'|' 'NF {print $1; exit}' | sed 's/[+ ].*$//')"
  case "$TERMINAL_STATE" in
    COMPLETED|FAILED|CANCELLED|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL|PREEMPTED|BOOT_FAIL|DEADLINE) break ;;
  esac
  sleep 10
done
case "$TERMINAL_STATE" in
  COMPLETED|FAILED|CANCELLED|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL|PREEMPTED|BOOT_FAIL|DEADLINE)
    SAFE_TO_PACKAGE=1
    ;;
  *)
    FINAL_STATUS="SEQ25_A34_INFRA_RETRY2_MONITOR_TIMEOUT_JOB_LEFT_RUNNING_NO_EVIDENCE"
    exit 58
    ;;
esac
sacct -j "$TRAINING_JOB_ID" --units=K --parsable2 --format=JobIDRaw,JobName,Partition,AllocCPUS,State,ExitCode,Elapsed,ReqMem,AllocTRES,MaxRSS,MaxVMSize > "${STATUS_DIRECTORY}/seq25_A34_infra_retry2_sacct_resources.txt"
printf '%s\n' "$TERMINAL_STATE" > "${STATUS_DIRECTORY}/training_terminal_state.txt"

WORKFLOW_STATUS_FILE="${STATUS_DIRECTORY}/workflow-status-${TRAINING_JOB_ID}.json"
if [[ "$TERMINAL_STATE" != "COMPLETED" ]]; then
  if [[ -f "$WORKFLOW_STATUS_FILE" && ! -L "$WORKFLOW_STATUS_FILE" ]] && python - "$WORKFLOW_STATUS_FILE" <<'PY'
import json
from pathlib import Path
import sys

workflow = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if workflow.get("status") != "RECOVERABLE_STOP" or int(workflow.get("recoverable_stop_evidence_exit_code", -1)) != 0:
    raise SystemExit(1)
PY
  then
    FINAL_STATUS="SEQ25_A34_INFRA_RETRY2_VERIFIED_RECOVERABLE_STOP"
    exit 75
  fi
  FINAL_STATUS="SEQ25_A34_INFRA_RETRY2_TRAINING_${TERMINAL_STATE:-UNKNOWN}_HARD_STOP"
  exit 59
fi
FINAL_STATUS="SEQ25_A34_INFRA_RETRY2_TRAINING_COMPLETED"

VERIFICATION_REPORT="${STATUS_DIRECTORY}/independent-verification-${TRAINING_JOB_ID}.json"
JOB_EVIDENCE_MANIFEST="${STATUS_DIRECTORY}/job-evidence-manifest-${TRAINING_JOB_ID}.json"
for path in "$WORKFLOW_STATUS_FILE" "$VERIFICATION_REPORT" "$JOB_EVIDENCE_MANIFEST" "${RUN_DIRECTORY}/result_summary.json" "${RUN_DIRECTORY}/manifest.sha256.json"; do
  [[ -f "$path" && ! -L "$path" ]] || { echo "scheduled A34 evidence absent or symbolic: $path" >&2; exit 60; }
done
python - "$RUN_BASE" "$WORKFLOW_STATUS_FILE" "$VERIFICATION_REPORT" "$JOB_EVIDENCE_MANIFEST" "${RUN_DIRECTORY}/result_summary.json" "$EXECUTION_ATTEMPT_ID" <<'PY'
from hashlib import sha256
import json
from pathlib import Path
import sys

remote_root = Path(sys.argv[1]).resolve()
workflow = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
verification = json.loads(Path(sys.argv[3]).read_text(encoding="utf-8"))
evidence = json.loads(Path(sys.argv[4]).read_text(encoding="utf-8"))
summary = json.loads(Path(sys.argv[5]).read_text(encoding="utf-8"))
experiment_id = "DAILY_CAMELS_NATIVE_KALMANNET_FULL_STATE_MASKED_NSE_SMOKE_V1_20260825_A34"
execution_attempt_id = sys.argv[6]

if any(document.get("experiment_id") != experiment_id for document in (verification, evidence, summary)):
    raise SystemExit("A34 scheduled evidence identity differs")
if (
    workflow.get("execution_attempt_id") != execution_attempt_id
    or evidence.get("execution_attempt_id") != execution_attempt_id
):
    raise SystemExit("A34 execution attempt identity differs")
status = workflow.get("status")
if status == "VERIFIED_SCIENTIFIC_PASS":
    expected = (0, 0, "VERIFIED_PASS", True)
elif status == "VERIFIED_SCIENTIFIC_HARD_STOP":
    expected = (3, 2, "VERIFIED_HARD_STOP", False)
else:
    raise SystemExit(f"unexpected completed A34 workflow status: {status}")
training_exit, verification_exit, verification_status, scientific_passed = expected
if (
    int(workflow.get("training_exit_code", -1)) != training_exit
    or int(workflow.get("verification_exit_code", -1)) != verification_exit
    or verification.get("status") != verification_status
    or verification.get("scientific_passed") is not scientific_passed
    or summary.get("science_gate", {}).get("passed") is not scientific_passed
    or verification.get("daily_only") is not True
    or verification.get("formal_evaluation") is not False
    or verification.get("reserved_evaluation_accessed") is not False
    or int(verification.get("optimizer_steps", -1)) != 8
    or int(verification.get("forecast_error_events", -1)) != 2160
):
    raise SystemExit("A34 workflow, verifier, and result summary differ")
if int(verification.get("selected_epoch", -1)) != int(summary.get("science_gate", {}).get("selected_epoch", -2)):
    raise SystemExit("A34 selected epoch binding differs")
files = evidence.get("files")
if not isinstance(files, dict) or int(evidence.get("file_count", -1)) != len(files):
    raise SystemExit("A34 job evidence manifest is incomplete")
for relative, record in files.items():
    relative_path = Path(str(relative))
    if relative_path.is_absolute() or ".." in relative_path.parts:
        raise SystemExit(f"unsafe A34 evidence member: {relative}")
    path = (remote_root / relative_path).resolve()
    try:
        path.relative_to(remote_root)
    except ValueError as exc:
        raise SystemExit(f"escaping A34 evidence member: {relative}") from exc
    if not path.is_file() or path.is_symlink():
        raise SystemExit(f"missing A34 evidence member: {relative}")
    content = path.read_bytes()
    if sha256(content).hexdigest() != record.get("sha256") or len(content) != int(record.get("size_bytes", -1)):
        raise SystemExit(f"changed A34 evidence member: {relative}")
print(json.dumps({
    "workflow_status": status,
    "scientific_passed": scientific_passed,
    "selected_epoch": verification["selected_epoch"],
    "epoch_validation_losses": verification["epoch_validation_losses"],
    "reasons": verification["reasons"],
    "optimizer_steps": verification["optimizer_steps"],
    "forecast_error_events": verification["forecast_error_events"],
}, sort_keys=True, separators=(",", ":")))
PY

FINAL_STATUS="SEQ25_A34_INFRA_RETRY2_SCHEDULED_EVIDENCE_VERIFIED"
WORKFLOW_STATUS="$(python - "$WORKFLOW_STATUS_FILE" <<'PY'
import json
from pathlib import Path
import sys
print(json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["status"])
PY
)"
if [[ "$WORKFLOW_STATUS" = "VERIFIED_SCIENTIFIC_PASS" ]]; then
  FINAL_STATUS="SEQ25_A34_INFRA_RETRY2_VERIFIED_SCIENTIFIC_PASS"
  echo "DAILY_CAMELS_NATIVE_KALMANNET_A34_INFRA_RETRY2_VERIFIED_SCIENTIFIC_PASS job=${TRAINING_JOB_ID}"
else
  FINAL_STATUS="SEQ25_A34_INFRA_RETRY2_VERIFIED_SCIENTIFIC_HARD_STOP"
  echo "DAILY_CAMELS_NATIVE_KALMANNET_A34_INFRA_RETRY2_VERIFIED_SCIENTIFIC_HARD_STOP job=${TRAINING_JOB_ID}"
fi
