#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

EXPECTED_USER="sunyiq"
MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
RESULT51="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_51.txt"
RESULT52="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_52.txt"
JOB_ID="215207"
EXPERIMENT_ID="DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_EPOCH10_TO40_RESUME_V1_20260826_A37"
EXECUTION_ATTEMPT_ID="DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_A37_A800_TRAIN1_SEQ51"
RUN_BASE="/data1/home/sunyiq/kalmannet_daily_camels_knet_a37_a800_probe1_20260827"
SOURCE_DIRECTORY="${RUN_BASE}/source_A37_a800_probe1_seq49"
RUN_DIRECTORY="${RUN_BASE}/runs/${EXPERIMENT_ID}"
STATUS_DIRECTORY="${RUN_BASE}/status"
LOG_OUT="${RUN_BASE}/logs/train-${JOB_ID}.out"
LOG_ERR="${RUN_BASE}/logs/train-${JOB_ID}.err"

sha256_file() {
  sha256sum "$1" | awk '{print $1}'
}

ACTUAL_USER="$(id -un)"
if [[ "${USER-}" != "$EXPECTED_USER" || "$ACTUAL_USER" != "$EXPECTED_USER" ]]; then
  echo "fixed-user check failed" >&2
  exit 50
fi
for receipt in "$RESULT51" "$RESULT52"; do
  [[ -f "$receipt" && ! -L "$receipt" ]] || {
    echo "required receipt is absent or symbolic: $receipt" >&2
    exit 51
  }
done
grep -Fq "SEQ51_A37_A800_TRAIN_SUBMITTED experiment_id=${EXPERIMENT_ID} execution_attempt_id=${EXECUTION_ATTEMPT_ID} training_job_id=${JOB_ID}" "$RESULT51" || {
  echo "sequence 51 training identity differs" >&2
  exit 52
}
grep -Fq "${JOB_ID}|daily-knet-a37-a800|sunyiq|hgpu8|FAILED|1:0" "$RESULT52" || {
  echo "sequence 52 does not prove the expected terminal failure" >&2
  exit 53
}
for directory in "$RUN_BASE" "$SOURCE_DIRECTORY" "$STATUS_DIRECTORY"; do
  [[ -d "$directory" && ! -L "$directory" ]] || {
    echo "required A37 directory is absent or symbolic: $directory" >&2
    exit 54
  }
done

printf 'SEQ53_A37_A800_SACCT_BEGIN\n'
sacct -j "$JOB_ID" --units=K --parsable2 \
  --format=JobIDRaw,JobName,User,Partition,State,ExitCode,Elapsed,NodeList,AllocCPUS,ReqMem,AllocTRES,ReqTRES,MaxRSS,MaxVMSize,AveRSS
printf 'SEQ53_A37_A800_SACCT_END\n'

printf 'SEQ53_A37_A800_FILE_INVENTORY_BEGIN\n'
while IFS= read -r -d '' path; do
  printf '%s|size=%s|sha256=%s\n' "$path" "$(stat -c '%s' "$path")" "$(sha256_file "$path")"
done < <(find "$RUN_BASE" -type f -print0 | sort -z)
printf 'SEQ53_A37_A800_FILE_INVENTORY_END\n'

printf 'SEQ53_A37_A800_LOCKS_BEGIN\n'
find "${STATUS_DIRECTORY}/locks" -mindepth 1 -maxdepth 2 -printf '%y|%p\n' | sort || true
printf 'SEQ53_A37_A800_LOCKS_END\n'

TEXT_FILES=(
  "$LOG_OUT"
  "$LOG_ERR"
  "${STATUS_DIRECTORY}/train-preflight-${EXPERIMENT_ID}-${JOB_ID}.json"
  "${STATUS_DIRECTORY}/train-gpu-resources-${EXPERIMENT_ID}-${JOB_ID}.csv"
  "${STATUS_DIRECTORY}/train-cgroup-resources-${EXPERIMENT_ID}-${JOB_ID}.txt"
  "${STATUS_DIRECTORY}/seq51_offline_train_bundle_verification.json"
  "${STATUS_DIRECTORY}/seq51_a800_train_submission_identity.txt"
  "${STATUS_DIRECTORY}/seq51_a800_training_job_id.txt"
  "${STATUS_DIRECTORY}/seq51_a800_training_submitted_time_utc.txt"
  "${STATUS_DIRECTORY}/seq51_pre_submission_squeue.txt"
  "${STATUS_DIRECTORY}/seq51_post_submission_squeue.txt"
  "${STATUS_DIRECTORY}/seq51_post_submission_sacct.txt"
  "${STATUS_DIRECTORY}/seq51_pre_submission_hgpu8_candidate_nodes.txt"
  "${STATUS_DIRECTORY}/locks/${EXPERIMENT_ID}.submission.lock/owner.txt"
  "${RUN_DIRECTORY}/events.jsonl"
  "${RUN_DIRECTORY}/epoch_history.json"
  "${RUN_DIRECTORY}/experiment_identity.json"
  "${RUN_DIRECTORY}/owner_evidence.json"
  "${RUN_DIRECTORY}/preflight.json"
  "${RUN_DIRECTORY}/result_summary.json"
  "${RUN_DIRECTORY}/completion.marker.json"
  "${RUN_DIRECTORY}/feature_diagnostics.json"
  "${RUN_DIRECTORY}/replay_evidence.json"
  "${RUN_DIRECTORY}/manifest.sha256.json"
)
for path in "${TEXT_FILES[@]}"; do
  if [[ -f "$path" && ! -L "$path" ]]; then
    printf 'SEQ53_A37_A800_CONTENT_BEGIN path=%s size=%s sha256=%s\n' \
      "$path" "$(stat -c '%s' "$path")" "$(sha256_file "$path")"
    sed -n '1,20000p' "$path"
    printf 'SEQ53_A37_A800_CONTENT_END path=%s\n' "$path"
  else
    printf 'SEQ53_A37_A800_CONTENT_ABSENT path=%s\n' "$path"
  fi
done

RESERVED_PATH_COUNT="$(find "$RUN_BASE" -type f -printf '%p\n' | grep -Eic 'held.?out|reserved.?evaluation|formal.?evaluation' || true)"
printf 'SEQ53_A37_A800_TERMINAL_COLLECTED experiment_id=%s execution_attempt_id=%s job_id=%s reserved_named_path_count=%s\n' \
  "$EXPERIMENT_ID" "$EXECUTION_ATTEMPT_ID" "$JOB_ID" "$RESERVED_PATH_COUNT"
