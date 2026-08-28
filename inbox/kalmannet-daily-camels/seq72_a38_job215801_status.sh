#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

EXPECTED_USER="sunyiq"
MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
RESULT71="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_71.txt"
RESULT71_SHA256="7395c0b89557392caca9e27d704b9c2e08c979a3c4f436fd8e2927f17643b5ff"
RESULT71_SIZE="1526"
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
[[ -f "$RESULT71" && ! -L "$RESULT71" ]] || {
  echo "sequence 71 receipt is absent, non-regular, or symbolic" >&2
  exit 54
}
[[ "$(stat -c '%s' "$RESULT71")" == "$RESULT71_SIZE" ]] || {
  echo "sequence 71 receipt size differs" >&2
  exit 55
}
[[ "$(sha256_file "$RESULT71")" == "$RESULT71_SHA256" ]] || {
  echo "sequence 71 receipt SHA-256 differs" >&2
  exit 56
}
grep -Fxq "SEQ71_A38_STATUS_QUERY experiment_id=${EXPERIMENT_ID} execution_attempt_id=${EXECUTION_ATTEMPT_ID} job_id=${JOB_ID} run_base=${RUN_BASE}" "$RESULT71" || {
  echo "sequence 71 status identity differs" >&2
  exit 57
}
grep -Fq "${JOB_ID}|daily-knet-a38|hgpu8|RUNNING|ngu202|" "$RESULT71" || {
  echo "sequence 71 did not prove the fixed job running on ngu202/hgpu8" >&2
  exit 58
}
grep -Fxq '### exit_code=0' "$RESULT71" || {
  echo "sequence 71 mailbox command did not complete successfully" >&2
  exit 59
}

printf 'SEQ72_A38_STATUS_QUERY experiment_id=%s execution_attempt_id=%s job_id=%s run_base=%s\n' \
  "$EXPERIMENT_ID" "$EXECUTION_ATTEMPT_ID" "$JOB_ID" "$RUN_BASE"
printf '%s\n' 'SEQ72_SQUEUE_BEGIN'
squeue -h -j "$JOB_ID" -o '%A|%j|%P|%T|%R|%M|%l|%b|%u|%Z|%o' 2>&1 || true
printf '%s\n' 'SEQ72_SQUEUE_END'
printf '%s\n' 'SEQ72_SACCT_BEGIN'
sacct -j "$JOB_ID" --parsable2 --format=JobIDRaw,JobName,User,Partition,State,ExitCode,Elapsed,Start,End,NodeList,AllocTRES,ReqTRES 2>&1 || true
printf '%s\n' 'SEQ72_SACCT_END'
