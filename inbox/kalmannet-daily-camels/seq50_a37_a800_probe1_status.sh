#!/usr/bin/env bash
set -Eeuo pipefail

EXPECTED_USER="sunyiq"
MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
RESULT49="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_49.txt"
JOB_ID="215199"
EXPERIMENT_ID="DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_EPOCH10_TO40_RESUME_V1_20260826_A37"
EXECUTION_ATTEMPT_ID="DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_A37_A800_PROBE1_SEQ49"
RUN_BASE="/data1/home/sunyiq/kalmannet_daily_camels_knet_a37_a800_probe1_20260827"
STATUS_DIRECTORY="${RUN_BASE}/status"
LOG_DIRECTORY="${RUN_BASE}/logs"
PROBE_REPORT="${STATUS_DIRECTORY}/probe-${EXPERIMENT_ID}-${JOB_ID}.json"
ENTRY_REPORT="${STATUS_DIRECTORY}/entry-probe-${EXPERIMENT_ID}-${JOB_ID}.json"
STDOUT_LOG="${LOG_DIRECTORY}/probe-${JOB_ID}.out"
STDERR_LOG="${LOG_DIRECTORY}/probe-${JOB_ID}.err"

if [[ "${USER-}" != "$EXPECTED_USER" || "$(id -un)" != "$EXPECTED_USER" ]]; then
  echo "fixed-user check failed" >&2
  exit 80
fi
[[ -f "$RESULT49" && ! -L "$RESULT49" ]] || {
  echo "sequence 49 receipt is absent or symbolic" >&2
  exit 81
}
grep -Fq "SEQ49_A37_A800_PROBE_SUBMITTED experiment_id=${EXPERIMENT_ID} execution_attempt_id=${EXECUTION_ATTEMPT_ID}" "$RESULT49" || {
  echo "sequence 49 experiment identity differs" >&2
  exit 82
}
grep -Fq "old_job_id=215178 old_terminal_state=CANCELLED new_job_id=${JOB_ID}" "$RESULT49" || {
  echo "sequence 49 job migration identity differs" >&2
  exit 83
}

printf '%s\n' 'SEQ50_SQUEUE_BEGIN'
squeue -h -j "$JOB_ID" -o '%A|%j|%P|%T|%R|%b|%C|%m|%Z|%o' || true
printf '%s\n' 'SEQ50_SQUEUE_END'
printf '%s\n' 'SEQ50_SACCT_BEGIN'
sacct -j "$JOB_ID" --parsable2 --format=JobIDRaw,JobName,User,Partition,State,ExitCode,Elapsed,NodeList,AllocTRES,ReqTRES,MaxRSS || true
printf '%s\n' 'SEQ50_SACCT_END'

STATE="$(sacct -n -X -j "$JOB_ID" --format=State -P 2>/dev/null | awk -F'|' 'NF {print $1; exit}' | sed 's/[+ ].*$//')"
printf 'SEQ50_A37_A800_PROBE_STATUS experiment_id=%s execution_attempt_id=%s job_id=%s state=%s\n' \
  "$EXPERIMENT_ID" "$EXECUTION_ATTEMPT_ID" "$JOB_ID" "${STATE:-UNKNOWN}"

case "$STATE" in
  PENDING|RUNNING|CONFIGURING|COMPLETING|SUSPENDED|RESIZING|REQUEUED|REQUEUE_FED)
    exit 0
    ;;
esac

for path in "$STDOUT_LOG" "$STDERR_LOG" "$PROBE_REPORT" "$ENTRY_REPORT"; do
  printf 'SEQ50_FILE path=%s exists=%s symbolic=%s size=%s sha256=%s\n' \
    "$path" "$([[ -f "$path" ]] && echo true || echo false)" \
    "$([[ -L "$path" ]] && echo true || echo false)" \
    "$([[ -f "$path" ]] && stat -c '%s' "$path" || echo NA)" \
    "$([[ -f "$path" && ! -L "$path" ]] && sha256sum "$path" | awk '{print $1}' || echo NA)"
done

for path in "$STDOUT_LOG" "$STDERR_LOG" "$PROBE_REPORT" "$ENTRY_REPORT"; do
  if [[ -f "$path" && ! -L "$path" ]]; then
    printf 'SEQ50_CONTENT_BEGIN path=%s\n' "$path"
    sed -n '1,800p' "$path"
    printf 'SEQ50_CONTENT_END path=%s\n' "$path"
  fi
done

printf '%s\n' 'SEQ50_LOCKS_BEGIN'
if [[ -d "${STATUS_DIRECTORY}/locks" && ! -L "${STATUS_DIRECTORY}/locks" ]]; then
  find "${STATUS_DIRECTORY}/locks" -mindepth 1 -maxdepth 2 -print -exec sed -n '1,80p' '{}' \; 2>/dev/null || true
else
  printf '%s\n' 'LOCK_DIRECTORY_ABSENT'
fi
printf '%s\n' 'SEQ50_LOCKS_END'
