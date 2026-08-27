#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

EXPECTED_USER="sunyiq"
MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
RESULT46="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_46.txt"
PROBE_JOB_ID="215178"

ACTUAL_USER="$(id -un)"
ACTUAL_UID="$(id -u)"
EXPECTED_UID="$(id -u "$EXPECTED_USER")"
if [[ "${USER-}" != "$EXPECTED_USER" || "$ACTUAL_USER" != "$EXPECTED_USER" || "$ACTUAL_UID" != "$EXPECTED_UID" ]]; then
  echo "fixed-user check failed" >&2
  exit 50
fi
[[ -f "$RESULT46" && ! -L "$RESULT46" ]] || {
  echo "sequence 46 receipt is absent or symbolic" >&2
  exit 51
}
grep -Fq "SEQ46_A37_GPU_AUDIT_COMPLETE job_id=${PROBE_JOB_ID}" "$RESULT46" || {
  echo "sequence 46 GPU audit did not complete" >&2
  exit 52
}

printf 'SEQ47_A37_PARTITION_ACCESS_IDENTITY user=%s job_id=%s\n' "$EXPECTED_USER" "$PROBE_JOB_ID"

printf 'SEQ47_JOB_STATUS_BEGIN\n'
squeue -j "$PROBE_JOB_ID" -o '%i|%j|%P|%T|%M|%D|%R|%b'
sacct -j "$PROBE_JOB_ID" --parsable2 --format=JobIDRaw,JobName,Partition,State,ExitCode,Elapsed,AllocTRES
printf 'SEQ47_JOB_STATUS_END\n'

set +e
printf 'SEQ47_JOB_PRIORITY_BEGIN\n'
sprio -j "$PROBE_JOB_ID" -l
priority_exit_code="$?"
printf 'SEQ47_JOB_PRIORITY_END exit_code=%s\n' "$priority_exit_code"

printf 'SEQ47_JOB_START_ESTIMATE_BEGIN\n'
squeue --start -j "$PROBE_JOB_ID" -o '%i|%j|%P|%T|%S|%R'
start_exit_code="$?"
printf 'SEQ47_JOB_START_ESTIMATE_END exit_code=%s\n' "$start_exit_code"

for partition in hgpu2p hgpu2 hgpu4 hgpu8; do
  printf 'SEQ47_PARTITION_BEGIN name=%s\n' "$partition"
  scontrol show partition "$partition" -o
  partition_exit_code="$?"
  printf 'SEQ47_PARTITION_END name=%s exit_code=%s\n' "$partition" "$partition_exit_code"
  if [[ "$partition_exit_code" -ne 0 ]]; then
    exit 53
  fi
done

printf 'SEQ47_USER_ASSOCIATION_BEGIN\n'
sacctmgr -n -P show assoc where user="$EXPECTED_USER" format=Cluster,Account,User,Partition,QOS,DefaultQOS
association_exit_code="$?"
printf 'SEQ47_USER_ASSOCIATION_END exit_code=%s\n' "$association_exit_code"
set -e

if [[ "$priority_exit_code" -ne 0 || "$start_exit_code" -ne 0 || "$association_exit_code" -ne 0 ]]; then
  echo "one or more read-only partition-access queries failed" >&2
  exit 54
fi
printf 'SEQ47_A37_PARTITION_ACCESS_AUDIT_COMPLETE job_id=%s\n' "$PROBE_JOB_ID"
