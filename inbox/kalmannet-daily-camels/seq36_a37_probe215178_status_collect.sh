#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

EXPECTED_USER="sunyiq"
MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
EXPERIMENT_ID="DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_EPOCH10_TO40_RESUME_V1_20260826_A37"
EXECUTION_ATTEMPT_ID="DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_A37_PROBE2_SEQ35"
PROBE_JOB_ID="215178"
RUN_BASE="/data1/home/sunyiq/kalmannet_daily_camels_knet_a37_resume1_20260826"
STATUS_DIRECTORY="${RUN_BASE}/status"
LOG_DIRECTORY="${RUN_BASE}/logs"
RUN_DIRECTORY="${RUN_BASE}/runs/${EXPERIMENT_ID}"
SEQ35_RESULT="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_35.txt"

ACTUAL_USER="$(id -un)"
ACTUAL_UID="$(id -u)"
EXPECTED_UID="$(id -u "$EXPECTED_USER")"
if [[ "${USER-}" != "$EXPECTED_USER" || "$ACTUAL_USER" != "$EXPECTED_USER" || "$ACTUAL_UID" != "$EXPECTED_UID" ]]; then
  echo "fixed-user check failed" >&2
  exit 50
fi
[[ -f "$SEQ35_RESULT" && ! -L "$SEQ35_RESULT" ]] || {
  echo "sequence 35 receipt is absent or symbolic" >&2
  exit 51
}
grep -Fq "SEQ35_A37_RESOURCE_PROBE2_SUBMITTED experiment_id=${EXPERIMENT_ID} execution_attempt_id=${EXECUTION_ATTEMPT_ID} job_id=${PROBE_JOB_ID} run_base=${RUN_BASE}" "$SEQ35_RESULT" || {
  echo "sequence 35 repaired probe identity differs" >&2
  exit 52
}

SACCT_OUTPUT="$(mktemp)"
SQUEUE_OUTPUT="$(mktemp)"
trap 'rm -f "$SACCT_OUTPUT" "$SQUEUE_OUTPUT"' EXIT
if ! sacct -j "$PROBE_JOB_ID" --units=K --parsable2 --format=JobIDRaw,JobName,Partition,AllocCPUS,State,ExitCode,Elapsed,ReqMem,AllocTRES,MaxRSS,MaxVMSize > "$SACCT_OUTPUT" 2>&1; then
  cat "$SACCT_OUTPUT"
  echo "SEQ36_A37_PROBE2_SACCT_QUERY_FAILED job_id=${PROBE_JOB_ID}" >&2
  exit 53
fi
set +e
squeue -j "$PROBE_JOB_ID" -o '%i|%j|%T|%M|%R' > "$SQUEUE_OUTPUT" 2>&1
SQUEUE_EXIT_CODE="$?"
set -e

printf 'SEQ36_A37_PROBE2_IDENTITY experiment_id=%s execution_attempt_id=%s job_id=%s run_base=%s\n' "$EXPERIMENT_ID" "$EXECUTION_ATTEMPT_ID" "$PROBE_JOB_ID" "$RUN_BASE"
printf 'SEQ36_A37_PROBE2_SACCT_BEGIN\n'
cat "$SACCT_OUTPUT"
printf 'SEQ36_A37_PROBE2_SACCT_END\n'
printf 'SEQ36_A37_PROBE2_SQUEUE_BEGIN exit_code=%s\n' "$SQUEUE_EXIT_CODE"
cat "$SQUEUE_OUTPUT"
printf 'SEQ36_A37_PROBE2_SQUEUE_END\n'

ROOT_RECORD="$(awk -F'|' -v id="$PROBE_JOB_ID" '$1 == id {print $5 "|" $6; exit}' "$SACCT_OUTPUT")"
ROOT_STATE="${ROOT_RECORD%%|*}"
ROOT_EXIT_CODE="${ROOT_RECORD#*|}"
ROOT_STATE="${ROOT_STATE%%+*}"
case "$ROOT_STATE" in
  COMPLETED|FAILED|CANCELLED|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL|PREEMPTED|BOOT_FAIL|DEADLINE|REVOKED|SPECIAL_EXIT)
    ;;
  *)
    printf 'SEQ36_A37_PROBE2_NON_TERMINAL state=%s exit_code=%s job_id=%s\n' "${ROOT_STATE:-UNKNOWN}" "${ROOT_EXIT_CODE:-UNKNOWN}" "$PROBE_JOB_ID"
    exit 0
    ;;
esac

report_file() {
  local relative="$1" path="${RUN_BASE}/$1"
  if [[ -f "$path" && ! -L "$path" ]]; then
    printf 'SEQ36_FILE_BEGIN\t%s\t%s\t%s\n' "$relative" "$(stat -c '%s' "$path")" "$(sha256sum "$path" | awk '{print $1}')"
    cat "$path"
    printf '\nSEQ36_FILE_END\t%s\n' "$relative"
  else
    printf 'SEQ36_FILE_MISSING_OR_NONREGULAR\t%s\n' "$relative"
  fi
}

report_file "status/probe-${EXPERIMENT_ID}-${PROBE_JOB_ID}.json"
report_file "status/entry-probe-${EXPERIMENT_ID}-${PROBE_JOB_ID}.json"
report_file "status/seq35_offline_A37.json"
report_file "status/seq35_submission_identity.txt"
report_file "status/seq35_probe_job_id.txt"
report_file "status/seq35_probe_submitted_time_utc.txt"
report_file "status/seq35_pre_submission_squeue.txt"
report_file "status/seq35_immediate_pre_submission_squeue.txt"
report_file "status/seq35_post_submission_squeue.txt"
report_file "logs/probe-${PROBE_JOB_ID}.out"
report_file "logs/probe-${PROBE_JOB_ID}.err"

if [[ -e "${STATUS_DIRECTORY}/locks/${EXPERIMENT_ID}.probe.lock" || -L "${STATUS_DIRECTORY}/locks/${EXPERIMENT_ID}.probe.lock" ]]; then
  printf 'SEQ36_A37_PROBE2_LOCK_CLEARED=false\n'
else
  printf 'SEQ36_A37_PROBE2_LOCK_CLEARED=true\n'
fi
if [[ -e "$RUN_DIRECTORY" || -L "$RUN_DIRECTORY" ]]; then
  printf 'SEQ36_A37_RUN_DIRECTORY_ABSENT=false\n'
else
  printf 'SEQ36_A37_RUN_DIRECTORY_ABSENT=true\n'
fi
printf 'SEQ36_A37_PROBE2_TERMINAL state=%s exit_code=%s job_id=%s\n' "$ROOT_STATE" "$ROOT_EXIT_CODE" "$PROBE_JOB_ID"
