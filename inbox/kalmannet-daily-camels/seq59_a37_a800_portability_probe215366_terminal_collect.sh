#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

EXPECTED_USER="sunyiq"
MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
RESULT57="$MAILBOX_ROOT/outbox/kalmannet-daily-camels/result_57.txt"
RESULT58="$MAILBOX_ROOT/outbox/kalmannet-daily-camels/result_58.txt"
JOB_ID="215366"
EXPERIMENT_ID="DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_EPOCH10_TO40_RESUME_V1_20260826_A37"
EXECUTION_ATTEMPT_ID="DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_A37_A800_PORTABILITY_PROBE2_SEQ57"
RUN_BASE="/data1/home/sunyiq/kalmannet_daily_camels_knet_a37_a800_portability_probe2_20260827"
SOURCE_DIRECTORY="$RUN_BASE/source_A37_a800_portability_probe2_seq57"
RUN_DIRECTORY="$RUN_BASE/runs/$EXPERIMENT_ID"
STATUS_DIRECTORY="$RUN_BASE/status"
LOG_OUT="$RUN_BASE/logs/portability-probe2-$JOB_ID.out"
LOG_ERR="$RUN_BASE/logs/portability-probe2-$JOB_ID.err"
SOURCE_CHECKPOINT_SHA256="b2b93f531c7ad4922e14d5479564e82e5a6dca553835bbc8cc8af61db4a8d81e"
SOURCE_CHECKPOINT_PATH="$SOURCE_DIRECTORY/artifacts/daily_camels_ukf_knet_parity_seq15_failure_evidence/ff2084c4/seq15_snapshot_2831/run/checkpoints/epoch_010.pt"
SOURCE_EPOCH_HISTORY_PATH="$SOURCE_DIRECTORY/artifacts/daily_camels_ukf_knet_parity_seq15_failure_evidence/ff2084c4/seq15_snapshot_2831/run/epoch_history.json"
SOURCE_DEVICE_REPORT_PATH="$SOURCE_DIRECTORY/artifacts/daily_camels_ukf_knet_parity_seq15_failure_evidence/ff2084c4/seq15_snapshot_2831/status/train-preflight-DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_TEN_EPOCH_V1_20260825_A16-211291.json"
SUBMISSION_LOCK="$STATUS_DIRECTORY/locks/$EXECUTION_ATTEMPT_ID.submission.lock"
TRAINING_LOCK="$STATUS_DIRECTORY/locks/$EXPERIMENT_ID.train.lock"
RUN_OWNER_LOCK="$RUN_DIRECTORY/.owner.lock"

sha256_file() {
  sha256sum "$1" | awk '{print $1}'
}

[[ "${USER-}" == "$EXPECTED_USER" && "$(id -un)" == "$EXPECTED_USER" ]] || {
  echo "fixed-user check failed" >&2
  exit 80
}
for receipt in "$RESULT57" "$RESULT58"; do
  [[ -f "$receipt" && ! -L "$receipt" ]] || {
    echo "required receipt is absent or symbolic: $receipt" >&2
    exit 81
  }
done
grep -Fq "SEQ57_A37_A800_PORTABILITY_PROBE_SUBMITTED experiment_id=$EXPERIMENT_ID execution_attempt_id=$EXECUTION_ATTEMPT_ID portability_probe_job_id=$JOB_ID" "$RESULT57" || {
  echo "sequence 57 portability-probe identity differs" >&2
  exit 82
}
grep -Fq "$JOB_ID|daily-knet-a37-pdiag|sunyiq|hgpu8|COMPLETED|0:0|" "$RESULT58" || {
  echo "sequence 58 does not prove the expected completed portability probe" >&2
  exit 83
}

IFS='|' read -r STATE EXIT_CODE JOB_NAME ACCOUNTING_USER PARTITION NODELIST _ < <(
  sacct -n -X -j "$JOB_ID" --parsable2 --format=State,ExitCode,JobName,User,Partition,NodeList |
    awk 'NF {print; exit}'
)
STATE="$(printf '%s' "$STATE" | sed 's/[+ ].*$//')"
[[ "$STATE" == "COMPLETED" && "$EXIT_CODE" == "0:0" ]] || {
  echo "portability probe terminal state changed: ${STATE:-UNKNOWN}/${EXIT_CODE:-UNKNOWN}" >&2
  exit 84
}
[[ "$JOB_NAME" == "daily-knet-a37-pdiag" && "$ACCOUNTING_USER" == "$EXPECTED_USER" ]] || {
  echo "portability probe Slurm identity differs: ${JOB_NAME:-UNKNOWN}/${ACCOUNTING_USER:-UNKNOWN}" >&2
  exit 85
}
[[ "$PARTITION" == "hgpu8" ]] || {
  echo "portability probe partition differs: ${PARTITION:-UNKNOWN}" >&2
  exit 86
}
case "$NODELIST" in
  ngu202|ngu203) ;;
  *) echo "portability probe node differs: ${NODELIST:-UNKNOWN}" >&2; exit 87 ;;
esac
for directory in "$RUN_BASE" "$SOURCE_DIRECTORY" "$RUN_DIRECTORY" "$STATUS_DIRECTORY"; do
  [[ -d "$directory" && ! -L "$directory" ]] || {
    echo "required portability-probe directory is absent or symbolic: $directory" >&2
    exit 88
  }
done
[[ -f "$SOURCE_CHECKPOINT_PATH" && ! -L "$SOURCE_CHECKPOINT_PATH" ]] || {
  echo "source checkpoint is absent or symbolic" >&2
  exit 89
}
ACTUAL_SOURCE_CHECKPOINT_SHA256="$(sha256_file "$SOURCE_CHECKPOINT_PATH")"
[[ "$ACTUAL_SOURCE_CHECKPOINT_SHA256" == "$SOURCE_CHECKPOINT_SHA256" ]] || {
  echo "source checkpoint SHA-256 differs" >&2
  exit 90
}

printf '%s\n' 'SEQ59_A37_A800_PORTABILITY_PROBE_SACCT_BEGIN'
sacct -j "$JOB_ID" --units=K --parsable2 \
  --format=JobIDRaw,JobName,User,Partition,State,ExitCode,Elapsed,NodeList,AllocCPUS,ReqMem,AllocTRES,ReqTRES,MaxRSS,MaxVMSize,AveRSS
printf '%s\n' 'SEQ59_A37_A800_PORTABILITY_PROBE_SACCT_END'

printf '%s\n' 'SEQ59_A37_A800_PORTABILITY_PROBE_SQUEUE_BEGIN'
squeue -h -j "$JOB_ID" -o '%A|%j|%P|%T|%R|%b|%C|%m|%l|%M|%Z|%o' || true
printf '%s\n' 'SEQ59_A37_A800_PORTABILITY_PROBE_SQUEUE_END'

printf '%s\n' 'SEQ59_A37_A800_PORTABILITY_PROBE_FILE_INVENTORY_BEGIN'
while IFS= read -r -d '' path; do
  printf '%s|size=%s|sha256=%s\n' "$path" "$(stat -c '%s' "$path")" "$(sha256_file "$path")"
done < <(find "$RUN_BASE" -type f -print0 | sort -z)
printf '%s\n' 'SEQ59_A37_A800_PORTABILITY_PROBE_FILE_INVENTORY_END'

printf '%s\n' 'SEQ59_A37_A800_PORTABILITY_PROBE_LOCKS_BEGIN'
find "$STATUS_DIRECTORY/locks" -mindepth 1 -maxdepth 2 -printf '%y|%p\n' | sort || true
for lock_path in "$TRAINING_LOCK" "$RUN_OWNER_LOCK" "$SUBMISSION_LOCK"; do
  if [[ -e "$lock_path" || -L "$lock_path" ]]; then
    printf 'present|%s\n' "$lock_path"
  else
    printf 'absent|%s\n' "$lock_path"
  fi
done
printf '%s\n' 'SEQ59_A37_A800_PORTABILITY_PROBE_LOCKS_END'

TEXT_FILES=(
  "$SOURCE_EPOCH_HISTORY_PATH"
  "$SOURCE_DEVICE_REPORT_PATH"
  "$LOG_OUT"
  "$LOG_ERR"
  "$STATUS_DIRECTORY/train-preflight-$EXPERIMENT_ID-$JOB_ID.json"
  "$STATUS_DIRECTORY/train-gpu-resources-$EXPERIMENT_ID-$JOB_ID.csv"
  "$STATUS_DIRECTORY/train-cgroup-resources-$EXPERIMENT_ID-$JOB_ID.txt"
  "$STATUS_DIRECTORY/seq57_offline_portability_probe_bundle_verification.json"
  "$STATUS_DIRECTORY/seq57_portability_probe_job_id.txt"
  "$STATUS_DIRECTORY/seq57_portability_probe_submitted_time_utc.txt"
  "$STATUS_DIRECTORY/seq57_post_submission_squeue.txt"
  "$STATUS_DIRECTORY/seq57_post_submission_sacct.txt"
  "$SUBMISSION_LOCK/owner.txt"
  "$RUN_DIRECTORY/events.jsonl"
  "$RUN_DIRECTORY/epoch_history.json"
  "$RUN_DIRECTORY/experiment_identity.json"
  "$RUN_DIRECTORY/owner_evidence.json"
  "$RUN_DIRECTORY/preflight.json"
  "$RUN_DIRECTORY/cross_device_portability_diagnostic.json"
  "$RUN_DIRECTORY/replay_evidence.json"
  "$RUN_DIRECTORY/feature_diagnostics.json"
  "$RUN_DIRECTORY/failure.json"
  "$RUN_DIRECTORY/result_summary.json"
  "$RUN_DIRECTORY/completion.marker.json"
  "$RUN_DIRECTORY/manifest.sha256.json"
)
for path in "${TEXT_FILES[@]}"; do
  if [[ -f "$path" && ! -L "$path" ]]; then
    printf 'SEQ59_A37_A800_PORTABILITY_PROBE_CONTENT_BEGIN path=%s size=%s sha256=%s\n' \
      "$path" "$(stat -c '%s' "$path")" "$(sha256_file "$path")"
    sed -n '1,20000p' "$path"
    printf 'SEQ59_A37_A800_PORTABILITY_PROBE_CONTENT_END path=%s\n' "$path"
  else
    printf 'SEQ59_A37_A800_PORTABILITY_PROBE_CONTENT_ABSENT path=%s\n' "$path"
  fi
done

BINARY_FILES=(
  "$SOURCE_CHECKPOINT_PATH"
  "$RUN_DIRECTORY/replay_predictions.npz"
  "$RUN_DIRECTORY/cross_device_epoch_000_actual.npz"
  "$RUN_DIRECTORY/cross_device_completed_epoch_actual.npz"
)
for path in "${BINARY_FILES[@]}"; do
  if [[ -f "$path" && ! -L "$path" ]]; then
    printf 'SEQ59_A37_A800_PORTABILITY_PROBE_BINARY path=%s size=%s sha256=%s\n' \
      "$path" "$(stat -c '%s' "$path")" "$(sha256_file "$path")"
  else
    printf 'SEQ59_A37_A800_PORTABILITY_PROBE_BINARY_ABSENT path=%s\n' "$path"
  fi
done

RESERVED_PATH_COUNT="$(find "$RUN_BASE" -type f -printf '%p\n' | grep -Eic 'held.?out|reserved.?evaluation|formal.?evaluation' || true)"
TRAINING_LOCK_PRESENT=0
RUN_OWNER_LOCK_PRESENT=0
SUBMISSION_LOCK_PRESENT=0
[[ ! -e "$TRAINING_LOCK" && ! -L "$TRAINING_LOCK" ]] || TRAINING_LOCK_PRESENT=1
[[ ! -e "$RUN_OWNER_LOCK" && ! -L "$RUN_OWNER_LOCK" ]] || RUN_OWNER_LOCK_PRESENT=1
[[ ! -d "$SUBMISSION_LOCK" || -L "$SUBMISSION_LOCK" ]] || SUBMISSION_LOCK_PRESENT=1
printf 'SEQ59_A37_A800_PORTABILITY_PROBE_TERMINAL_COLLECTED experiment_id=%s execution_attempt_id=%s job_id=%s terminal_state=%s terminal_exit_code=%s partition=%s node=%s source_checkpoint_sha256=%s reserved_named_path_count=%s training_lock_present=%s run_owner_lock_present=%s submission_lock_present=%s\n' \
  "$EXPERIMENT_ID" "$EXECUTION_ATTEMPT_ID" "$JOB_ID" "$STATE" "$EXIT_CODE" "$PARTITION" "$NODELIST" "$ACTUAL_SOURCE_CHECKPOINT_SHA256" "$RESERVED_PATH_COUNT" "$TRAINING_LOCK_PRESENT" "$RUN_OWNER_LOCK_PRESENT" "$SUBMISSION_LOCK_PRESENT"
