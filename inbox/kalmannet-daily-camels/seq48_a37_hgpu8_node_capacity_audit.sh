#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

EXPECTED_USER="sunyiq"
MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
RESULT47="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_47.txt"
PROBE_JOB_ID="215178"

ACTUAL_USER="$(id -un)"
ACTUAL_UID="$(id -u)"
EXPECTED_UID="$(id -u "$EXPECTED_USER")"
if [[ "${USER-}" != "$EXPECTED_USER" || "$ACTUAL_USER" != "$EXPECTED_USER" || "$ACTUAL_UID" != "$EXPECTED_UID" ]]; then
  echo "fixed-user check failed" >&2
  exit 50
fi
[[ -f "$RESULT47" && ! -L "$RESULT47" ]] || {
  echo "sequence 47 receipt is absent or symbolic" >&2
  exit 51
}
grep -Fq "SEQ47_A37_PARTITION_ACCESS_AUDIT_COMPLETE job_id=${PROBE_JOB_ID}" "$RESULT47" || {
  echo "sequence 47 partition access audit did not complete" >&2
  exit 52
}

printf 'SEQ48_A37_HGPU8_CAPACITY_IDENTITY user=%s old_probe_job_id=%s\n' "$EXPECTED_USER" "$PROBE_JOB_ID"
printf 'SEQ48_OLD_PROBE_STATUS_BEGIN\n'
squeue -j "$PROBE_JOB_ID" -o '%i|%j|%P|%T|%M|%D|%R|%b'
sacct -j "$PROBE_JOB_ID" --parsable2 --format=JobIDRaw,JobName,Partition,State,ExitCode,Elapsed,AllocTRES
printf 'SEQ48_OLD_PROBE_STATUS_END\n'

printf 'SEQ48_HGPU8_QUEUE_BEGIN\n'
sinfo -N -p hgpu8 -o '%N|%P|%t|%G|%C|%m|%e'
squeue -p hgpu8 -o '%i|%j|%u|%T|%M|%D|%R|%b'
printf 'SEQ48_HGPU8_QUEUE_END\n'

for node in ngu201 ngu202 ngu203; do
  printf 'SEQ48_NODE_BEGIN name=%s\n' "$node"
  scontrol show node "$node" -o
  printf 'SEQ48_NODE_END name=%s\n' "$node"
done

printf 'SEQ48_A37_HGPU8_CAPACITY_AUDIT_COMPLETE old_probe_job_id=%s\n' "$PROBE_JOB_ID"
