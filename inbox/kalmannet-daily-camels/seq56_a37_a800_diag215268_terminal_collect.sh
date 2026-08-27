#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

EXPECTED_USER="sunyiq"
MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
RESULT54="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_54.txt"
RESULT55="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_55.txt"
JOB_ID="215268"
EXPERIMENT_ID="DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_EPOCH10_TO40_RESUME_V1_20260826_A37"
EXECUTION_ATTEMPT_ID="DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_A37_A800_DIAG1_SEQ54"
RUN_BASE="/data1/home/sunyiq/kalmannet_daily_camels_knet_a37_a800_diag1_20260827"
SOURCE_DIRECTORY="${RUN_BASE}/source_A37_a800_diag1_seq54"
RUN_DIRECTORY="${RUN_BASE}/runs/${EXPERIMENT_ID}"
STATUS_DIRECTORY="${RUN_BASE}/status"
LOG_OUT="${RUN_BASE}/logs/diag-${JOB_ID}.out"
LOG_ERR="${RUN_BASE}/logs/diag-${JOB_ID}.err"

sha256_file() {
  sha256sum "$1" | awk '{print $1}'
}

[[ "${USER-}" == "$EXPECTED_USER" && "$(id -un)" == "$EXPECTED_USER" ]] || {
  echo "fixed-user check failed" >&2
  exit 80
}
for receipt in "$RESULT54" "$RESULT55"; do
  [[ -f "$receipt" && ! -L "$receipt" ]] || {
    echo "required receipt is absent or symbolic: $receipt" >&2
    exit 81
  }
done
grep -Fq "SEQ54_A37_A800_DIAGNOSTIC_SUBMITTED experiment_id=${EXPERIMENT_ID} execution_attempt_id=${EXECUTION_ATTEMPT_ID} diagnostic_job_id=${JOB_ID}" "$RESULT54" || {
  echo "sequence 54 diagnostic identity differs" >&2
  exit 82
}
grep -Fq "${JOB_ID}|daily-knet-a37-diag|sunyiq|hgpu8|FAILED|1:0" "$RESULT55" || {
  echo "sequence 55 does not prove the expected terminal diagnostic failure" >&2
  exit 83
}

STATE="$(sacct -n -X -j "$JOB_ID" --format=State -P | awk -F'|' 'NF {print $1; exit}' | sed 's/[+ ].*$//')"
EXIT_CODE="$(sacct -n -X -j "$JOB_ID" --format=ExitCode -P | awk -F'|' 'NF {print $1; exit}')"
[[ "$STATE" == "FAILED" && "$EXIT_CODE" == "1:0" ]] || {
  echo "diagnostic terminal state changed: ${STATE:-UNKNOWN}/${EXIT_CODE:-UNKNOWN}" >&2
  exit 84
}
for directory in "$RUN_BASE" "$SOURCE_DIRECTORY" "$STATUS_DIRECTORY"; do
  [[ -d "$directory" && ! -L "$directory" ]] || {
    echo "required diagnostic directory is absent or symbolic: $directory" >&2
    exit 85
  }
done

printf '%s\n' 'SEQ56_A37_A800_DIAGNOSTIC_SACCT_BEGIN'
sacct -j "$JOB_ID" --units=K --parsable2 \
  --format=JobIDRaw,JobName,User,Partition,State,ExitCode,Elapsed,NodeList,AllocCPUS,ReqMem,AllocTRES,ReqTRES,MaxRSS,MaxVMSize,AveRSS
printf '%s\n' 'SEQ56_A37_A800_DIAGNOSTIC_SACCT_END'

printf '%s\n' 'SEQ56_A37_A800_DIAGNOSTIC_FILE_INVENTORY_BEGIN'
while IFS= read -r -d '' path; do
  printf '%s|size=%s|sha256=%s\n' "$path" "$(stat -c '%s' "$path")" "$(sha256_file "$path")"
done < <(find "$RUN_BASE" -type f -print0 | sort -z)
printf '%s\n' 'SEQ56_A37_A800_DIAGNOSTIC_FILE_INVENTORY_END'

printf '%s\n' 'SEQ56_A37_A800_DIAGNOSTIC_LOCKS_BEGIN'
find "${STATUS_DIRECTORY}/locks" -mindepth 1 -maxdepth 2 -printf '%y|%p\n' | sort || true
printf '%s\n' 'SEQ56_A37_A800_DIAGNOSTIC_LOCKS_END'

TEXT_FILES=(
  "$LOG_OUT"
  "$LOG_ERR"
  "${STATUS_DIRECTORY}/train-preflight-${EXPERIMENT_ID}-${JOB_ID}.json"
  "${STATUS_DIRECTORY}/train-gpu-resources-${EXPERIMENT_ID}-${JOB_ID}.csv"
  "${STATUS_DIRECTORY}/train-cgroup-resources-${EXPERIMENT_ID}-${JOB_ID}.txt"
  "${STATUS_DIRECTORY}/seq54_offline_bundle_verification.json"
  "${STATUS_DIRECTORY}/seq54_diagnostic_job_id.txt"
  "${STATUS_DIRECTORY}/seq54_diagnostic_submitted_time_utc.txt"
  "${STATUS_DIRECTORY}/seq54_post_submission_squeue.txt"
  "${STATUS_DIRECTORY}/seq54_post_submission_sacct.txt"
  "${STATUS_DIRECTORY}/locks/${EXECUTION_ATTEMPT_ID}.submission.lock/owner.txt"
  "${RUN_DIRECTORY}/events.jsonl"
  "${RUN_DIRECTORY}/experiment_identity.json"
  "${RUN_DIRECTORY}/owner_evidence.json"
  "${RUN_DIRECTORY}/preflight.json"
  "${RUN_DIRECTORY}/failure.json"
  "${RUN_DIRECTORY}/result_summary.json"
  "${RUN_DIRECTORY}/completion.marker.json"
  "${RUN_DIRECTORY}/manifest.sha256.json"
)
for path in "${TEXT_FILES[@]}"; do
  if [[ -f "$path" && ! -L "$path" ]]; then
    printf 'SEQ56_A37_A800_DIAGNOSTIC_CONTENT_BEGIN path=%s size=%s sha256=%s\n' \
      "$path" "$(stat -c '%s' "$path")" "$(sha256_file "$path")"
    sed -n '1,20000p' "$path"
    printf 'SEQ56_A37_A800_DIAGNOSTIC_CONTENT_END path=%s\n' "$path"
  else
    printf 'SEQ56_A37_A800_DIAGNOSTIC_CONTENT_ABSENT path=%s\n' "$path"
  fi
done

RESERVED_PATH_COUNT="$(find "$RUN_BASE" -type f -printf '%p\n' | grep -Eic 'held.?out|reserved.?evaluation|formal.?evaluation' || true)"
printf 'SEQ56_A37_A800_DIAGNOSTIC_TERMINAL_COLLECTED experiment_id=%s execution_attempt_id=%s job_id=%s terminal_state=%s terminal_exit_code=%s reserved_named_path_count=%s\n' \
  "$EXPERIMENT_ID" "$EXECUTION_ATTEMPT_ID" "$JOB_ID" "$STATE" "$EXIT_CODE" "$RESERVED_PATH_COUNT"
