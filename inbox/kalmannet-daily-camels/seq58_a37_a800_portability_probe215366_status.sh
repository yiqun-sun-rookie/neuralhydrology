#!/usr/bin/env bash
set -Eeuo pipefail

EXPECTED_USER="sunyiq"
MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
RESULT57="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_57.txt"
JOB_ID="215366"
EXPERIMENT_ID="DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_EPOCH10_TO40_RESUME_V1_20260826_A37"
EXECUTION_ATTEMPT_ID="DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_A37_A800_PORTABILITY_PROBE2_SEQ57"

[[ "${USER-}" == "$EXPECTED_USER" && "$(id -un)" == "$EXPECTED_USER" ]] || {
  echo "fixed-user check failed" >&2
  exit 80
}
[[ -f "$RESULT57" && ! -L "$RESULT57" ]] || {
  echo "sequence 57 receipt absent or symbolic" >&2
  exit 81
}
grep -Fq "SEQ57_A37_A800_PORTABILITY_PROBE_SUBMITTED experiment_id=${EXPERIMENT_ID} execution_attempt_id=${EXECUTION_ATTEMPT_ID} portability_probe_job_id=${JOB_ID}" "$RESULT57" || {
  echo "sequence 57 portability-probe identity differs" >&2
  exit 82
}

printf '%s\n' 'SEQ58_SQUEUE_BEGIN'
squeue -h -j "$JOB_ID" -o '%A|%j|%P|%T|%R|%b|%C|%m|%l|%M|%Z|%o' || true
printf '%s\n' 'SEQ58_SQUEUE_END'
printf '%s\n' 'SEQ58_SACCT_BEGIN'
sacct -j "$JOB_ID" --units=K --parsable2 --format=JobIDRaw,JobName,User,Partition,State,ExitCode,Elapsed,NodeList,AllocCPUS,ReqMem,AllocTRES,ReqTRES,MaxRSS,MaxVMSize || true
printf '%s\n' 'SEQ58_SACCT_END'
printf 'SEQ58_A37_A800_PORTABILITY_PROBE_STATUS_QUERIED experiment_id=%s execution_attempt_id=%s job_id=%s\n' "$EXPERIMENT_ID" "$EXECUTION_ATTEMPT_ID" "$JOB_ID"
