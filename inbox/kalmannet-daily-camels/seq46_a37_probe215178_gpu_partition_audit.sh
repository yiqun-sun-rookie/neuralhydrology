#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

EXPECTED_USER="sunyiq"
MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
RESULT45="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_45.txt"
EXPERIMENT_ID="DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_EPOCH10_TO40_RESUME_V1_20260826_A37"
EXECUTION_ATTEMPT_ID="DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_A37_PROBE2_SEQ35"
PROBE_JOB_ID="215178"

ACTUAL_USER="$(id -un)"
ACTUAL_UID="$(id -u)"
EXPECTED_UID="$(id -u "$EXPECTED_USER")"
if [[ "${USER-}" != "$EXPECTED_USER" || "$ACTUAL_USER" != "$EXPECTED_USER" || "$ACTUAL_UID" != "$EXPECTED_UID" ]]; then
  echo "fixed-user check failed" >&2
  exit 50
fi
[[ -f "$RESULT45" && ! -L "$RESULT45" ]] || {
  echo "sequence 45 receipt is absent or symbolic" >&2
  exit 51
}
grep -Fq "SEQ45_A37_PROBE2_NON_TERMINAL state=PENDING exit_code=0:0 job_id=${PROBE_JOB_ID}" "$RESULT45" || {
  echo "sequence 45 is not the expected pending receipt" >&2
  exit 52
}

printf 'SEQ46_A37_GPU_AUDIT_IDENTITY experiment_id=%s execution_attempt_id=%s job_id=%s\n' \
  "$EXPERIMENT_ID" "$EXECUTION_ATTEMPT_ID" "$PROBE_JOB_ID"

printf 'SEQ46_A37_PROBE2_SACCT_BEGIN\n'
sacct -j "$PROBE_JOB_ID" --units=K --parsable2 \
  --format=JobIDRaw,JobName,Partition,AllocCPUS,State,ExitCode,Elapsed,ReqMem,AllocTRES,MaxRSS,MaxVMSize
printf 'SEQ46_A37_PROBE2_SACCT_END\n'

printf 'SEQ46_A37_PROBE2_SQUEUE_BEGIN\n'
squeue -j "$PROBE_JOB_ID" -o '%i|%j|%P|%T|%M|%D|%R|%b'
printf 'SEQ46_A37_PROBE2_SQUEUE_END\n'

set +e
printf 'SEQ46_GPU_PARTITIONS_BEGIN\n'
sinfo -h -o '%P|%a|%l|%D|%t|%G|%C|%m'
partition_exit_code="$?"
printf 'SEQ46_GPU_PARTITIONS_END exit_code=%s\n' "$partition_exit_code"

printf 'SEQ46_GPU_NODES_BEGIN\n'
sinfo -h -N -o '%N|%P|%T|%f|%G|%m|%c|%e'
nodes_exit_code="$?"
printf 'SEQ46_GPU_NODES_END exit_code=%s\n' "$nodes_exit_code"

printf 'SEQ46_GPU_TRES_BEGIN\n'
scontrol show node -o | awk '/Gres=.*gpu/ || /CfgTRES=.*gres\/gpu/'
tres_exit_code="${PIPESTATUS[0]}"
printf 'SEQ46_GPU_TRES_END exit_code=%s\n' "$tres_exit_code"
set -e

if [[ "$partition_exit_code" -ne 0 || "$nodes_exit_code" -ne 0 || "$tres_exit_code" -ne 0 ]]; then
  echo "one or more read-only GPU inventory queries failed" >&2
  exit 53
fi
printf 'SEQ46_A37_GPU_AUDIT_COMPLETE job_id=%s\n' "$PROBE_JOB_ID"
