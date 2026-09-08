#!/bin/bash
set -eo pipefail
printf '%s\n' 'channel=kalmannet-daily-perbasin sequence=71 purpose=corrected-shared-resource-and-exact-root-readonly'
date -u '+observed_at_utc=%Y-%m-%dT%H:%M:%SZ'
date '+observed_at_seconds=%s'
hostname
id -un
task_query_failures=0
task_read() {
  printf 'READ_COMMAND'
  printf ' %q' "$@"
  printf '\n'
  if "$@"; then
    printf '%s\n' 'READ_COMMAND_EXIT=0'
  else
    task_rc=$?
    printf 'READ_COMMAND_EXIT=%s\n' "$task_rc"
    task_query_failures=$((task_query_failures + 1))
  fi
}
task_root=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908
if [ -e "$task_root" ] || [ -L "$task_root" ]; then
  printf '%s\n' 'EXACT_PROPOSED_ROOT_EXISTS=YES'
  task_read ls -ld -- "$task_root"
else
  printf '%s\n' 'EXACT_PROPOSED_ROOT_EXISTS=NO'
fi
for task_ancestor in /data1 /data1/home /data1/home/sunyiq; do
  task_read ls -ld -- "$task_ancestor"
  task_read readlink -f -- "$task_ancestor"
  if [ -L "$task_ancestor" ]; then printf 'ANCESTOR_LINK=%s\n' "$task_ancestor"; task_query_failures=$((task_query_failures + 1)); fi
done
printf '%s\n' 'A800_PARTITION_AND_NODES'
task_read scontrol show partition hgpu8
task_read sinfo -N -p hgpu8 -h -o '%N|%T|%c|%C|%G|%E'
task_read sinfo -N -p hgpu8 -h -O NodeHost,Gres,GresUsed,CPUsState,StateLong
task_read scontrol show node ngu201
task_read scontrol show node ngu202
task_read scontrol show node ngu203
printf '%s\n' 'OWN_EXPANDED_ACTIVE_JOB_PATHS'
task_read squeue -r -u sunyiq -h -o '%i|%j|%T|%P|%D|%C|%b|%Z|%R'
if task_job_ids=$(squeue -r -u sunyiq -h -o '%i'); then
  for task_job_id in $task_job_ids; do
    if [[ "$task_job_id" =~ ^[0-9]+(_[0-9]+)?$ ]]; then
      task_read scontrol show job -dd "$task_job_id"
    else
      printf 'UNEXPECTED_JOB_IDENTIFIER=%s\n' "$task_job_id"
      task_query_failures=$((task_query_failures + 1))
    fi
  done
else
  printf '%s\n' 'OWN_JOB_ENUMERATION_FAILED'
  task_query_failures=$((task_query_failures + 1))
fi
printf '%s\n' 'ACCOUNT_ASSOCIATION'
task_read sacctmgr -n -P show assoc where user=sunyiq format=Cluster,Account,User,Partition,MaxJobs,MaxSubmit,MaxTRES,GrpTRES
printf '%s\n' 'SUBMISSION_COMMAND_IDENTITY'
task_read type sbatch
printf '%s\n' 'SCHEDULER_SELECTION_CONFIGURATION'
if task_scheduler_config=$(scontrol show config); then
  printf '%s\n' "$task_scheduler_config" | awk '/SelectType|SelectTypeParameters|TaskPlugin|PrivateData|SchedulerType/ {print}'
else
  printf '%s\n' 'SCHEDULER_CONFIGURATION_QUERY_FAILED'
  task_query_failures=$((task_query_failures + 1))
fi
printf 'READONLY_COMPLETE task_writes=0 compute_submissions=0 checkpoint_reads=0 prediction_array_reads=0 query_failures=%s\n' "$task_query_failures"
if [ "$task_query_failures" -ne 0 ]; then exit 1; fi
