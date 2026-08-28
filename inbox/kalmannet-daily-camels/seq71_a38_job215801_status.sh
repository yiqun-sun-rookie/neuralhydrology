#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

EXPECTED_USER="sunyiq"
MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
RESULT70="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_70.txt"
RESULT70_SHA256="7b72da67bc1c9fa6e36c35e1d2f49656e4e27037fe52eee5d6e556594e276077"
RESULT70_SIZE="12788"
JOB_ID="215801"
EXPERIMENT_ID="DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_EPOCH40_TO80_RESUME_STEP_MONOTONICITY_DIAGNOSTIC_V1_20260828_A38"
EXECUTION_ATTEMPT_ID="DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_A38_A800_TRAIN1_SEQ70"
RUN_BASE="/data1/home/sunyiq/kalmannet_daily_camels_knet_a38_a800_train1_20260828"

sha256_file() {
  sha256sum "$1" | awk '{print $1}'
}

[[ "${USER-}" == "$EXPECTED_USER" && "$(id -un)" == "$EXPECTED_USER" ]] || {
  echo "fixed-user check failed" >&2
  exit 53
}
[[ -f "$RESULT70" && ! -L "$RESULT70" ]] || {
  echo "sequence 70 receipt is absent, non-regular, or symbolic" >&2
  exit 54
}
[[ "$(stat -c '%s' "$RESULT70")" == "$RESULT70_SIZE" ]] || {
  echo "sequence 70 receipt size differs" >&2
  exit 55
}
[[ "$(sha256_file "$RESULT70")" == "$RESULT70_SHA256" ]] || {
  echo "sequence 70 receipt SHA-256 differs" >&2
  exit 56
}
grep -Fxq "SEQ70_A38_A800_TRAIN_SUBMITTED experiment_id=${EXPERIMENT_ID} execution_attempt_id=${EXECUTION_ATTEMPT_ID} training_job_id=${JOB_ID} run_base=${RUN_BASE} archive_sha256=753dbcb1238bdbe9b9b590408fad6ba0838764ba17ff9556c694f58512a7327e outer_manifest_sha256=b4f000430cbb7395150211742b60c70834f5fe186f126835ee9fa5dac9884adf wrapper_sha256=34787a955d06bcde0ede6a4c7c556e50967ce5a34d0b8ba90a77d54a967df7a0 source_checkpoint_sha256=43ed17aaacabdae7e88a80de8567ac3d29d88635d93f701016c757e7f3a407f5 source_recovery_receipt_sha256=017e99754d12badebb0b9ddf4b1b7566c86645e6c0ee306d0409affe41287f85 target_partition=hgpu8 target_node=ngu202 target_gpu=NVIDIA_A800-SXM4-80GB" "$RESULT70" || {
  echo "sequence 70 unique-submission marker differs" >&2
  exit 57
}
grep -Fxq '### exit_code=0' "$RESULT70" || {
  echo "sequence 70 mailbox command did not complete successfully" >&2
  exit 58
}

printf 'SEQ71_A38_STATUS_QUERY experiment_id=%s execution_attempt_id=%s job_id=%s run_base=%s\n' \
  "$EXPERIMENT_ID" "$EXECUTION_ATTEMPT_ID" "$JOB_ID" "$RUN_BASE"
printf '%s\n' 'SEQ71_SQUEUE_BEGIN'
squeue -h -j "$JOB_ID" -o '%A|%j|%P|%T|%R|%M|%l|%b|%u|%Z|%o' 2>&1 || true
printf '%s\n' 'SEQ71_SQUEUE_END'
printf '%s\n' 'SEQ71_SACCT_BEGIN'
sacct -j "$JOB_ID" --parsable2 --format=JobIDRaw,JobName,User,Partition,State,ExitCode,Elapsed,Start,End,NodeList,AllocTRES,ReqTRES 2>&1 || true
printf '%s\n' 'SEQ71_SACCT_END'
