#!/usr/bin/env bash
set -Eeuo pipefail

EXPECTED_USER="sunyiq"
MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
RESULT54="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_54.txt"
JOB_ID="215268"
EXPERIMENT_ID="DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_EPOCH10_TO40_RESUME_V1_20260826_A37"
EXECUTION_ATTEMPT_ID="DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_A37_A800_DIAG1_SEQ54"

[[ "${USER-}" == "$EXPECTED_USER" && "$(id -un)" == "$EXPECTED_USER" ]] || {
  echo "fixed-user check failed" >&2
  exit 80
}
[[ -f "$RESULT54" && ! -L "$RESULT54" ]] || {
  echo "sequence 54 receipt absent or symbolic" >&2
  exit 81
}
grep -Fq "SEQ54_A37_A800_DIAGNOSTIC_SUBMITTED experiment_id=${EXPERIMENT_ID} execution_attempt_id=${EXECUTION_ATTEMPT_ID} diagnostic_job_id=${JOB_ID}" "$RESULT54" || {
  echo "sequence 54 identity differs" >&2
  exit 82
}

printf '%s\n' 'SEQ55_SQUEUE_BEGIN'
squeue -h -j "$JOB_ID" -o '%A|%j|%P|%T|%R|%b|%C|%m|%l|%M|%Z|%o' || true
printf '%s\n' 'SEQ55_SQUEUE_END'
printf '%s\n' 'SEQ55_SACCT_BEGIN'
sacct -j "$JOB_ID" --units=K --parsable2 --format=JobIDRaw,JobName,User,Partition,State,ExitCode,Elapsed,NodeList,AllocCPUS,ReqMem,AllocTRES,ReqTRES,MaxRSS,MaxVMSize || true
printf '%s\n' 'SEQ55_SACCT_END'
printf 'SEQ55_A37_A800_DIAGNOSTIC_STATUS_QUERIED experiment_id=%s execution_attempt_id=%s job_id=%s\n' "$EXPERIMENT_ID" "$EXECUTION_ATTEMPT_ID" "$JOB_ID"
