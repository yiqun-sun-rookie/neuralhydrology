#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

EXPECTED_USER="sunyiq"
MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
ARCHIVE="${MAILBOX_ROOT}/payload/kalmannet-daily-camels/official-tsp-gru-causal-fair-a31-partition-default-v20/DAILY_CAMELS_OFFICIAL_KALMANNET_TUKF06_CAUSAL_FAIR_RESOURCE_SMOKE_V3_20260825_A31.tar.gz"
ARCHIVE_SHA256="485cfd289674205444507ad59d4c0bd666648608ca444012db3a5e2ef4e06784"
ARCHIVE_SIZE=1171461
EXPERIMENT_ID="DAILY_CAMELS_OFFICIAL_KALMANNET_TUKF06_CAUSAL_FAIR_RESOURCE_SMOKE_V3_20260825_A31"
RUN_BASE="/data1/home/sunyiq/kalmannet_daily_camels_official_tsp_gru_causal_fair_a31_20260825"
SOURCE_DIRECTORY="${RUN_BASE}/source_A31_seq20"
RUN_DIRECTORY="${RUN_BASE}/${EXPERIMENT_ID}"
STATUS_DIRECTORY="${RUN_BASE}/status"
STAGING_DIRECTORY="/data1/home/sunyiq/kalmannet_daily_camels_official_tsp_gru_causal_fair_a31_staging_20260825"
OUTBOX_DIRECTORY="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels"
EVIDENCE_ARCHIVE="${OUTBOX_DIRECTORY}/DAILY_CAMELS_OFFICIAL_KALMANNET_CAUSAL_FAIR_A31_SEQ20_evidence.tar.gz"
NAMESPACE_OWNED=0
SAFE_TO_PACKAGE=0
FINAL_STATUS="SEQ20_A31_STARTED"
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
[[ -f "$ARCHIVE" && ! -L "$ARCHIVE" ]] || { echo "A31 archive absent or symbolic" >&2; exit 51; }
[[ "$(stat -c '%s' "$ARCHIVE")" = "$ARCHIVE_SIZE" ]] || { echo "A31 archive size differs" >&2; exit 52; }
[[ "$(sha256_file "$ARCHIVE")" = "$ARCHIVE_SHA256" ]] || { echo "A31 archive hash differs" >&2; exit 53; }
for path in "$RUN_BASE" "$STAGING_DIRECTORY" "$EVIDENCE_ARCHIVE"; do
  [[ ! -e "$path" && ! -L "$path" ]] || { echo "isolated A31 path already exists: $path" >&2; exit 54; }
done

mkdir "$RUN_BASE" "$STAGING_DIRECTORY"
mkdir "$SOURCE_DIRECTORY" "$STATUS_DIRECTORY" "$RUN_BASE/logs"
NAMESPACE_OWNED=1
SAFE_TO_PACKAGE=1
trap on_exit EXIT
trap 'FINAL_STATUS="SEQ20_A31_INTERRUPTED"; exit 143' INT TERM
date -u +%Y-%m-%dT%H:%M:%SZ > "${STATUS_DIRECTORY}/started_time_utc.txt"
{
  printf 'archive=%s\n' "$ARCHIVE"
  printf 'archive_sha256=%s\n' "$ARCHIVE_SHA256"
  printf 'archive_size_bytes=%s\n' "$ARCHIVE_SIZE"
} > "${STATUS_DIRECTORY}/payload_archive_identity.txt"
FINAL_STATUS="SEQ20_A31_NAMESPACE_OWNED"
tar -xzf "$ARCHIVE" -C "$SOURCE_DIRECTORY"
set +u
source "/data1/home/${USER}/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
cd "$SOURCE_DIRECTORY"
python -u hpc/daily_camels_official_kalmannet_causal_fair/preflight.py --bundle-root "$SOURCE_DIRECTORY" --offline-bundle-check > "${STATUS_DIRECTORY}/offline-preflight.json"
FINAL_STATUS="SEQ20_A31_OFFLINE_BUNDLE_VERIFIED"

SAFE_TO_PACKAGE=0
if ! TRAINING_JOB_ID="$(sbatch --parsable hpc/daily_camels_official_kalmannet_causal_fair/submit_resource_smoke_gpu.slurm)"; then
  SAFE_TO_PACKAGE=1
  FINAL_STATUS="SEQ20_A31_SUBMISSION_REJECTED_HARD_STOP"
  exit 55
fi
[[ "$TRAINING_JOB_ID" =~ ^[0-9]+$ ]] || { FINAL_STATUS="SEQ20_A31_SUBMISSION_IDENTITY_HARD_STOP"; exit 58; }
printf '%s\n' "$TRAINING_JOB_ID" > "${STATUS_DIRECTORY}/training_job_id.txt"
FINAL_STATUS="SEQ20_A31_SUBMITTED"

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
    FINAL_STATUS="SEQ20_A31_MONITOR_TIMEOUT_JOB_LEFT_RUNNING_NO_EVIDENCE"
    exit 57
    ;;
esac
sacct -j "$TRAINING_JOB_ID" --units=K --parsable2 --format=JobIDRaw,JobName,Partition,AllocCPUS,State,ExitCode,Elapsed,ReqMem,MaxRSS,MaxVMSize > "${STATUS_DIRECTORY}/seq20_A31_sacct_resources.txt"
printf '%s\n' "$TERMINAL_STATE" > "${STATUS_DIRECTORY}/training_terminal_state.txt"
if [[ "$TERMINAL_STATE" != "COMPLETED" ]]; then
  FINAL_STATUS="SEQ20_A31_TRAINING_${TERMINAL_STATE:-UNKNOWN}_HARD_STOP"
  exit 56
fi
FINAL_STATUS="SEQ20_A31_TRAINING_COMPLETED"

python -u hpc/daily_camels_official_kalmannet_causal_fair/verify_smoke.py --run-directory "$RUN_DIRECTORY" --status-directory "$STATUS_DIRECTORY" --job-id "$TRAINING_JOB_ID" --output "${STATUS_DIRECTORY}/independent_verification.json"
FINAL_STATUS="SEQ20_A31_INDEPENDENTLY_VERIFIED"
python - "$STATUS_DIRECTORY/independent_verification.json" <<'PY'
import json
from pathlib import Path
import sys
report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if report.get("status") != "TECHNICAL_EVIDENCE_VERIFIED":
    raise SystemExit("A31 independent verification status differs")
print(json.dumps(report, sort_keys=True))
PY
FINAL_STATUS="SEQ20_A31_RESOURCE_AND_POST_ZERO_TRAINING_EFFECT_VERIFIED"
echo "DAILY_CAMELS_OFFICIAL_KALMANNET_A31_RESOURCE_AND_POST_ZERO_TRAINING_EFFECT_PASS job=${TRAINING_JOB_ID}"
