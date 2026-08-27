#!/usr/bin/env bash
set -euo pipefail

JOB_ID="215207"
EXPERIMENT_ID="DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_EPOCH10_TO40_RESUME_V1_20260826_A37"
EXECUTION_ATTEMPT_ID="DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_A37_A800_TRAIN1_SEQ51"

printf 'SEQ52_A37_A800_SQUEUE_BEGIN\n'
squeue -h -j "$JOB_ID" -o '%A|%j|%P|%T|%R|%b|%C|%m|%l|%M|%Z|%o' || true
printf 'SEQ52_A37_A800_SQUEUE_END\n'
printf 'SEQ52_A37_A800_SACCT_BEGIN\n'
sacct -j "$JOB_ID" --units=K --parsable2 \
  --format=JobIDRaw,JobName,User,Partition,State,ExitCode,Elapsed,NodeList,AllocCPUS,ReqMem,AllocTRES,ReqTRES,MaxRSS,MaxVMSize
printf 'SEQ52_A37_A800_SACCT_END\n'
printf 'SEQ52_A37_A800_STATUS_QUERIED experiment_id=%s execution_attempt_id=%s job_id=%s\n' \
  "$EXPERIMENT_ID" "$EXECUTION_ATTEMPT_ID" "$JOB_ID"
