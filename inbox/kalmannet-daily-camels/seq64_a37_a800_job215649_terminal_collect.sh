#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

EXPECTED_USER="sunyiq"
MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
RESULT61="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_61.txt"
RESULT63="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_63.txt"
RESULT61_SHA256="b13499659b67a6414395d68eadabfbdb6f54fcb1853e8ce40ee3200c9eaaab35"
RESULT63_SHA256="e2d3b273c3c733e85e59d09bd11eab506531ba9e76af4c618410c89ba85dce0b"
JOB_ID="215649"
EXPERIMENT_ID="DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_EPOCH10_TO40_RESUME_V1_20260826_A37"
EXECUTION_ATTEMPT_ID="DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_A37_A800_TRAIN3_SEQ61"
RUN_BASE="/data1/home/sunyiq/kalmannet_daily_camels_knet_a37_a800_train3_20260827"
SOURCE_DIRECTORY="${RUN_BASE}/source_A37_a800_train3_seq61"
RUN_DIRECTORY="${RUN_BASE}/runs/${EXPERIMENT_ID}"
STATUS_DIRECTORY="${RUN_BASE}/status"
LOG_OUT="${RUN_BASE}/logs/train3-${JOB_ID}.out"
LOG_ERR="${RUN_BASE}/logs/train3-${JOB_ID}.err"

sha256_file() {
  sha256sum "$1" | awk '{print $1}'
}

require_regular_identity() {
  local path="$1" expected_sha256="$2" expected_size="$3" label="$4"
  [[ -f "$path" && ! -L "$path" ]] || {
    echo "${label} is absent, non-regular, or symbolic: ${path}" >&2
    return 50
  }
  [[ "$(stat -c '%s' "$path")" == "$expected_size" ]] || {
    echo "${label} size differs" >&2
    return 51
  }
  [[ "$(sha256_file "$path")" == "$expected_sha256" ]] || {
    echo "${label} SHA-256 differs" >&2
    return 52
  }
}

[[ "${USER-}" == "$EXPECTED_USER" && "$(id -un)" == "$EXPECTED_USER" ]] || {
  echo "fixed-user check failed" >&2
  exit 53
}
require_regular_identity "$RESULT61" "$RESULT61_SHA256" "11899" "sequence 61 submission receipt"
require_regular_identity "$RESULT63" "$RESULT63_SHA256" "663" "sequence 63 terminal accounting receipt"
grep -Fq "SEQ61_A37_A800_TRAIN_SUBMITTED experiment_id=${EXPERIMENT_ID} execution_attempt_id=${EXECUTION_ATTEMPT_ID} training_job_id=${JOB_ID} run_base=${RUN_BASE}" "$RESULT61" || {
  echo "sequence 61 formal training identity differs" >&2
  exit 54
}
grep -Fq "${JOB_ID}|daily-knet-a37|sunyiq|hgpu8|FAILED|1:0|00:00:04|ngu202" "$RESULT63" || {
  echo "sequence 63 does not prove the expected terminal failure" >&2
  exit 55
}

IFS='|' read -r STATE EXIT_CODE JOB_NAME ACCOUNTING_USER PARTITION NODELIST _ < <(
  sacct -n -X -j "$JOB_ID" --parsable2 --format=State,ExitCode,JobName,User,Partition,NodeList |
    awk 'NF {print; exit}'
)
STATE="$(printf '%s' "$STATE" | sed 's/[+ ].*$//')"
[[ "$STATE" == "FAILED" && "$EXIT_CODE" == "1:0" ]] || {
  echo "formal training terminal state changed: ${STATE:-UNKNOWN}/${EXIT_CODE:-UNKNOWN}" >&2
  exit 56
}
[[ "$JOB_NAME" == "daily-knet-a37" && "$ACCOUNTING_USER" == "$EXPECTED_USER" && "$PARTITION" == "hgpu8" && "$NODELIST" == "ngu202" ]] || {
  echo "formal training Slurm identity differs: ${JOB_NAME:-UNKNOWN}/${ACCOUNTING_USER:-UNKNOWN}/${PARTITION:-UNKNOWN}/${NODELIST:-UNKNOWN}" >&2
  exit 57
}
for directory in "$RUN_BASE" "$SOURCE_DIRECTORY" "$STATUS_DIRECTORY"; do
  [[ -d "$directory" && ! -L "$directory" ]] || {
    echo "required formal training directory is absent or symbolic: $directory" >&2
    exit 58
  }
done

printf '%s\n' 'SEQ64_A37_A800_SACCT_BEGIN'
sacct -j "$JOB_ID" --units=K --parsable2 \
  --format=JobIDRaw,JobName,User,Partition,State,ExitCode,Elapsed,NodeList,AllocCPUS,ReqMem,AllocTRES,ReqTRES,MaxRSS,MaxVMSize,AveRSS
printf '%s\n' 'SEQ64_A37_A800_SACCT_END'

printf '%s\n' 'SEQ64_A37_A800_FILE_INVENTORY_BEGIN'
while IFS= read -r -d '' path; do
  printf '%s|size=%s|sha256=%s\n' "$path" "$(stat -c '%s' "$path")" "$(sha256_file "$path")"
done < <(find "$RUN_BASE" -type f -print0 | sort -z)
printf '%s\n' 'SEQ64_A37_A800_FILE_INVENTORY_END'

printf '%s\n' 'SEQ64_A37_A800_LOCKS_BEGIN'
find "${STATUS_DIRECTORY}/locks" -mindepth 1 -maxdepth 2 -printf '%y|%p\n' | sort || true
printf '%s\n' 'SEQ64_A37_A800_LOCKS_END'

TEXT_FILES=(
  "$LOG_OUT"
  "$LOG_ERR"
  "${STATUS_DIRECTORY}/train-preflight-${EXPERIMENT_ID}-${JOB_ID}.json"
  "${STATUS_DIRECTORY}/train-gpu-resources-${EXPERIMENT_ID}-${JOB_ID}.csv"
  "${STATUS_DIRECTORY}/train-cgroup-resources-${EXPERIMENT_ID}-${JOB_ID}.txt"
  "${STATUS_DIRECTORY}/seq61_offline_train_bundle_verification.json"
  "${STATUS_DIRECTORY}/seq61_a800_train_submission_identity.txt"
  "${STATUS_DIRECTORY}/seq61_a800_training_job_id.txt"
  "${STATUS_DIRECTORY}/seq61_a800_training_submitted_time_utc.txt"
  "${STATUS_DIRECTORY}/seq61_pre_submission_squeue.txt"
  "${STATUS_DIRECTORY}/seq61_post_submission_squeue.txt"
  "${STATUS_DIRECTORY}/seq61_post_submission_sacct.txt"
  "${STATUS_DIRECTORY}/seq61_pre_submission_hgpu8_candidate_nodes.txt"
  "${STATUS_DIRECTORY}/locks/${EXECUTION_ATTEMPT_ID}.submission.lock/owner.txt"
  "${RUN_DIRECTORY}/events.jsonl"
  "${RUN_DIRECTORY}/epoch_history.json"
  "${RUN_DIRECTORY}/experiment_identity.json"
  "${RUN_DIRECTORY}/owner_evidence.json"
  "${RUN_DIRECTORY}/preflight.json"
  "${RUN_DIRECTORY}/failure.json"
  "${RUN_DIRECTORY}/result_summary.json"
  "${RUN_DIRECTORY}/completion.marker.json"
  "${RUN_DIRECTORY}/feature_diagnostics.json"
  "${RUN_DIRECTORY}/replay_evidence.json"
  "${RUN_DIRECTORY}/cross_device_portability_diagnostic.json"
  "${RUN_DIRECTORY}/manifest.sha256.json"
)
for path in "${TEXT_FILES[@]}"; do
  if [[ -f "$path" && ! -L "$path" ]]; then
    printf 'SEQ64_A37_A800_CONTENT_BEGIN path=%s size=%s sha256=%s\n' \
      "$path" "$(stat -c '%s' "$path")" "$(sha256_file "$path")"
    sed -n '1,30000p' "$path"
    printf 'SEQ64_A37_A800_CONTENT_END path=%s\n' "$path"
  else
    printf 'SEQ64_A37_A800_CONTENT_ABSENT path=%s\n' "$path"
  fi
done

RESERVED_PATH_COUNT="$(find "$RUN_BASE" -type f -printf '%p\n' | grep -Eic 'held.?out|reserved.?evaluation|formal.?evaluation' || true)"
TRAIN_LOCK_PRESENT=0
RUN_OWNER_LOCK_PRESENT=0
[[ -e "${STATUS_DIRECTORY}/locks/${EXPERIMENT_ID}.train.lock" || -L "${STATUS_DIRECTORY}/locks/${EXPERIMENT_ID}.train.lock" ]] && TRAIN_LOCK_PRESENT=1
[[ -e "${RUN_DIRECTORY}/.owner.lock" || -L "${RUN_DIRECTORY}/.owner.lock" ]] && RUN_OWNER_LOCK_PRESENT=1
printf 'SEQ64_A37_A800_TERMINAL_COLLECTED experiment_id=%s execution_attempt_id=%s job_id=%s terminal_state=%s terminal_exit_code=%s partition=%s node=%s reserved_named_path_count=%s training_lock_present=%s run_owner_lock_present=%s\n' \
  "$EXPERIMENT_ID" "$EXECUTION_ATTEMPT_ID" "$JOB_ID" "$STATE" "$EXIT_CODE" "$PARTITION" "$NODELIST" "$RESERVED_PATH_COUNT" "$TRAIN_LOCK_PRESENT" "$RUN_OWNER_LOCK_PRESENT"
