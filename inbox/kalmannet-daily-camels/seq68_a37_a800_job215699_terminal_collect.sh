#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

EXPECTED_USER="sunyiq"
MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
RESULT65="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_65.txt"
RESULT67="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_67.txt"
RESULT65_SHA256="25d2de64c489b6998ad4056f0f69641c3841941ab61faae40be64a5db4e6a2df"
RESULT67_SHA256="590a47bae822e11a633f9daee2d6358e22526b30252251fd17221a204efc6b09"
JOB_ID="215699"
EXPERIMENT_ID="DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_EPOCH10_TO40_RESUME_V1_20260826_A37"
EXECUTION_ATTEMPT_ID="DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_A37_A800_TRAIN4_SEQ65"
RUN_BASE="/data1/home/sunyiq/kalmannet_daily_camels_knet_a37_a800_train4_20260827"
SOURCE_DIRECTORY="${RUN_BASE}/source_A37_a800_train4_seq65"
RUN_DIRECTORY="${RUN_BASE}/runs/${EXPERIMENT_ID}"
STATUS_DIRECTORY="${RUN_BASE}/status"
LOG_OUT="${RUN_BASE}/logs/train4-${JOB_ID}.out"
LOG_ERR="${RUN_BASE}/logs/train4-${JOB_ID}.err"
TRAIN_LOCK="${STATUS_DIRECTORY}/locks/${EXPERIMENT_ID}.train.lock"
RUN_OWNER_LOCK="${RUN_DIRECTORY}/.owner.lock"
SUBMISSION_OWNER="${STATUS_DIRECTORY}/locks/${EXECUTION_ATTEMPT_ID}.submission.lock/owner.txt"

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

reserved_named_path() {
  shopt -s nocasematch
  if [[ "$1" =~ held.?out|reserved.?evaluation|formal.?evaluation ]]; then
    shopt -u nocasematch
    return 0
  fi
  shopt -u nocasematch
  return 1
}

[[ "${USER-}" == "$EXPECTED_USER" && "$(id -un)" == "$EXPECTED_USER" ]] || {
  echo "fixed-user check failed" >&2
  exit 53
}

require_regular_identity "$RESULT65" "$RESULT65_SHA256" "12098" "sequence 65 submission receipt"
require_regular_identity "$RESULT67" "$RESULT67_SHA256" "728" "sequence 67 terminal accounting receipt"
grep -Fxq "SEQ65_A37_A800_TRAIN_SUBMITTED experiment_id=${EXPERIMENT_ID} execution_attempt_id=${EXECUTION_ATTEMPT_ID} training_job_id=${JOB_ID} run_base=${RUN_BASE} archive_sha256=758c43ac6823b7e306b04871fa77a5bbd6e66981ee02cc6b8ec0b83d8ac08044 wrapper_sha256=6c6b7281a37216787e5c9ff56b935213dd3297d6c457141daf6e419e555086a5 source_checkpoint_sha256=b2b93f531c7ad4922e14d5479564e82e5a6dca553835bbc8cc8af61db4a8d81e portability_receipt_sha256=747c304f1ec12d551d4b8b6f6a525fe28c9d757313c9fd009a741f8a3dcfacae recovered_submission_receipt_sha256=b13499659b67a6414395d68eadabfbdb6f54fcb1853e8ce40ee3200c9eaaab35 recovered_failure_receipt_sha256=c2963dc0f4bb023d2e68886ba3a543f8c4e5459e39397c5112880f2683123a34 target_partition=hgpu8 excluded_node=ngu201" "$RESULT65" || {
  echo "sequence 65 formal training identity differs" >&2
  exit 54
}
grep -Fxq '### exit_code=0' "$RESULT65" || {
  echo "sequence 65 mailbox command did not complete successfully" >&2
  exit 55
}
grep -Fq "${JOB_ID}|daily-knet-a37|sunyiq|hgpu8|FAILED|2:0|00:21:33|ngu202" "$RESULT67" || {
  echo "sequence 67 does not prove the expected terminal failure" >&2
  exit 56
}
grep -Fxq '### exit_code=0' "$RESULT67" || {
  echo "sequence 67 status query did not complete successfully" >&2
  exit 57
}

ACCOUNTING_LINE="$(
  sacct -n -X -j "$JOB_ID" --parsable2 --format=State,ExitCode,JobName,User,Partition,NodeList |
    awk 'NF {print; exit}'
)"
[[ -n "$ACCOUNTING_LINE" ]] || {
  echo "formal training accounting is empty" >&2
  exit 58
}
IFS='|' read -r STATE EXIT_CODE JOB_NAME ACCOUNTING_USER PARTITION NODELIST _ <<<"$ACCOUNTING_LINE"
STATE="$(printf '%s' "$STATE" | sed 's/[+ ].*$//')"
[[ "$STATE" == "FAILED" && "$EXIT_CODE" == "2:0" ]] || {
  echo "formal training terminal state changed: ${STATE:-UNKNOWN}/${EXIT_CODE:-UNKNOWN}" >&2
  exit 58
}
[[ "$JOB_NAME" == "daily-knet-a37" && "$ACCOUNTING_USER" == "$EXPECTED_USER" && "$PARTITION" == "hgpu8" && "$NODELIST" == "ngu202" ]] || {
  echo "formal training Slurm identity differs" >&2
  exit 59
}
set +e
SQUEUE_SNAPSHOT="$(squeue -h -j "$JOB_ID" -o '%A|%j|%P|%T|%R|%b|%Z|%o' 2>&1)"
SQUEUE_EXIT_CODE="$?"
set -e
printf '%s\n' 'SEQ68_A37_A800_SQUEUE_BEGIN' "$SQUEUE_SNAPSHOT" 'SEQ68_A37_A800_SQUEUE_END'
if [[ "$SQUEUE_EXIT_CODE" == "0" && -n "$SQUEUE_SNAPSHOT" ]]; then
  echo "terminal job unexpectedly remains active" >&2
  exit 60
fi
if [[ "$SQUEUE_EXIT_CODE" != "0" && "$SQUEUE_SNAPSHOT" != *"Invalid job id specified"* ]]; then
  echo "target-only squeue query failed unexpectedly" >&2
  exit 60
fi

for directory in "$RUN_BASE" "$SOURCE_DIRECTORY" "$STATUS_DIRECTORY"; do
  [[ -d "$directory" && ! -L "$directory" ]] || {
    echo "required formal training directory is absent or symbolic: $directory" >&2
    exit 61
  }
done

printf '%s\n' 'SEQ68_A37_A800_SACCT_BEGIN'
sacct -j "$JOB_ID" --units=K --parsable2 \
  --format=JobIDRaw,JobName,User,Partition,State,ExitCode,Elapsed,NodeList,AllocCPUS,ReqMem,AllocTRES,ReqTRES,MaxRSS,MaxVMSize,AveRSS
printf '%s\n' 'SEQ68_A37_A800_SACCT_END'

RESERVED_PATH_COUNT=0
declare -A SAFE_REGULAR_FILES=()
shopt -s nullglob dotglob
inventory_directory() {
  local directory="$1" path file_size file_sha256
  [[ -d "$directory" && ! -L "$directory" && -r "$directory" && -x "$directory" ]] || {
    echo "inventory directory is absent, symbolic, or unreadable: $directory" >&2
    return 62
  }
  for path in "$directory"/*; do
    if reserved_named_path "$path"; then
      RESERVED_PATH_COUNT=$((RESERVED_PATH_COUNT + 1))
      printf '%s|RESERVED_NAMED_PATH_SKIPPED\n' "$path"
    elif [[ -L "$path" ]]; then
      printf '%s|SYMBOLIC_LINK_SKIPPED\n' "$path"
    elif [[ -d "$path" ]]; then
      inventory_directory "$path"
    elif [[ -f "$path" ]]; then
      file_size="$(stat -c '%s' "$path")"
      file_sha256="$(sha256_file "$path")"
      SAFE_REGULAR_FILES["$path"]="1"
      printf '%s|size=%s|sha256=%s\n' "$path" "$file_size" "$file_sha256"
    else
      printf '%s|NON_REGULAR_PATH_SKIPPED\n' "$path"
    fi
  done
  return 0
}

lock_inventory_directory() {
  local directory="$1" path path_type
  [[ -d "$directory" && ! -L "$directory" && -r "$directory" && -x "$directory" ]] || {
    echo "lock inventory directory is absent, symbolic, or unreadable: $directory" >&2
    return 63
  }
  for path in "$directory"/*; do
    if [[ -L "$path" ]]; then
      path_type="l"
    elif [[ -d "$path" ]]; then
      path_type="d"
    elif [[ -f "$path" ]]; then
      path_type="f"
    else
      path_type="o"
    fi
    printf '%s|%s\n' "$path_type" "$path"
    if [[ "$path_type" == "d" ]]; then
      lock_inventory_directory "$path"
    fi
  done
  return 0
}

printf '%s\n' 'SEQ68_A37_A800_FILE_INVENTORY_BEGIN'
inventory_directory "$RUN_BASE"
printf '%s\n' 'SEQ68_A37_A800_FILE_INVENTORY_END'

printf '%s\n' 'SEQ68_A37_A800_LOCKS_BEGIN'
lock_inventory_directory "${STATUS_DIRECTORY}/locks"
printf '%s\n' 'SEQ68_A37_A800_LOCKS_END'

TEXT_FILES=(
  "$LOG_OUT"
  "$LOG_ERR"
  "${STATUS_DIRECTORY}/train-preflight-${EXPERIMENT_ID}-${JOB_ID}.json"
  "${STATUS_DIRECTORY}/train-gpu-resources-${EXPERIMENT_ID}-${JOB_ID}.csv"
  "${STATUS_DIRECTORY}/train-cgroup-resources-${EXPERIMENT_ID}-${JOB_ID}.txt"
  "${STATUS_DIRECTORY}/seq65_offline_train_bundle_verification.json"
  "${STATUS_DIRECTORY}/seq65_a800_train_submission_identity.txt"
  "${STATUS_DIRECTORY}/seq65_a800_training_job_id.txt"
  "${STATUS_DIRECTORY}/seq65_a800_training_submitted_time_utc.txt"
  "${STATUS_DIRECTORY}/seq65_pre_submission_squeue.txt"
  "${STATUS_DIRECTORY}/seq65_post_submission_squeue.txt"
  "${STATUS_DIRECTORY}/seq65_post_submission_sacct.txt"
  "${STATUS_DIRECTORY}/seq65_pre_submission_hgpu8_candidate_nodes.txt"
  "$SUBMISSION_OWNER"
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
  if reserved_named_path "$path"; then
    printf 'SEQ68_A37_A800_CONTENT_SKIPPED_RESERVED_NAME path=%s\n' "$path"
  elif [[ "${SAFE_REGULAR_FILES[$path]-}" == "1" && -f "$path" && ! -L "$path" ]]; then
    FILE_SIZE="$(stat -c '%s' "$path")"
    FILE_SHA256="$(sha256_file "$path")"
    printf 'SEQ68_A37_A800_CONTENT_BEGIN path=%s size=%s sha256=%s\n' \
      "$path" "$FILE_SIZE" "$FILE_SHA256"
    sed -n '1,30000p' "$path"
    printf 'SEQ68_A37_A800_CONTENT_END path=%s\n' "$path"
  else
    printf 'SEQ68_A37_A800_CONTENT_ABSENT_OR_UNSAFE path=%s\n' "$path"
  fi
done

RUN_DIRECTORY_PRESENT=0
TRAIN_LOCK_PRESENT=0
RUN_OWNER_LOCK_PRESENT=0
COMPLETION_MARKER_PRESENT=0
FAILURE_FILE_PRESENT=0
if [[ -d "$RUN_DIRECTORY" && ! -L "$RUN_DIRECTORY" ]]; then
  RUN_DIRECTORY_PRESENT=1
fi
if [[ -e "$TRAIN_LOCK" || -L "$TRAIN_LOCK" ]]; then
  TRAIN_LOCK_PRESENT=1
fi
if [[ -e "$RUN_OWNER_LOCK" || -L "$RUN_OWNER_LOCK" ]]; then
  RUN_OWNER_LOCK_PRESENT=1
fi
if [[ -f "${RUN_DIRECTORY}/completion.marker.json" && ! -L "${RUN_DIRECTORY}/completion.marker.json" ]]; then
  COMPLETION_MARKER_PRESENT=1
fi
if [[ -f "${RUN_DIRECTORY}/failure.json" && ! -L "${RUN_DIRECTORY}/failure.json" ]]; then
  FAILURE_FILE_PRESENT=1
fi

printf 'SEQ68_A37_A800_TERMINAL_COLLECTED experiment_id=%s execution_attempt_id=%s job_id=%s terminal_state=%s terminal_exit_code=%s partition=%s node=%s reserved_named_path_count=%s run_directory_present=%s completion_marker_present=%s failure_file_present=%s training_lock_present=%s run_owner_lock_present=%s\n' \
  "$EXPERIMENT_ID" "$EXECUTION_ATTEMPT_ID" "$JOB_ID" "$STATE" "$EXIT_CODE" "$PARTITION" "$NODELIST" "$RESERVED_PATH_COUNT" "$RUN_DIRECTORY_PRESENT" "$COMPLETION_MARKER_PRESENT" "$FAILURE_FILE_PRESENT" "$TRAIN_LOCK_PRESENT" "$RUN_OWNER_LOCK_PRESENT"
