#!/bin/bash
set -eo pipefail
printf '%s\n' 'channel=kalmannet-daily-perbasin sequence=70 purpose=21-basin-development-shared-resource-and-exact-root-readonly'
date -u '+observed_at_utc=%Y-%m-%dT%H:%M:%SZ'
date '+observed_at_seconds=%s'
hostname
id -un
task_root=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_21_development_20260908
if [ -e "$task_root" ] || [ -L "$task_root" ]; then
    printf '%s\n' 'EXACT_PROPOSED_ROOT_EXISTS=YES'
    ls -ld -- "$task_root"
else
    printf '%s\n' 'EXACT_PROPOSED_ROOT_EXISTS=NO'
fi
printf '%s\n' 'PROPOSED_ROOT_ANCESTORS'
ls -ld -- /data1 /data1/home /data1/home/sunyiq
printf '%s\n' 'A800_PARTITION'
scontrol show partition hgpu8
printf '%s\n' 'A800_NODES'
sinfo -N -p hgpu8 -h -o '%N|%T|%c|%C|%G|%E'
scontrol show node ngu201
scontrol show node ngu202
scontrol show node ngu203
printf '%s\n' 'OWN_ACTIVE_JOB_PATHS'
squeue -u sunyiq -h -o '%i|%j|%T|%P|%D|%C|%b|%Z|%R'
task_job_ids=$(squeue -u sunyiq -h -o '%i')
for task_job_id in $task_job_ids; do
    scontrol show job -dd "$task_job_id"
done
printf '%s\n' 'ACCOUNT_ASSOCIATION'
sacctmgr -n -P show assoc where user=sunyiq format=Cluster,Account,User,Partition,MaxJobs,MaxSubmit,MaxTRES,GrpTRES
printf '%s\n' 'SUBMISSION_COMMAND_IDENTITY'
type sbatch
printf '%s\n' 'READONLY_COMPLETE task_writes=0 compute_submissions=0 checkpoint_reads=0 prediction_array_reads=0'
