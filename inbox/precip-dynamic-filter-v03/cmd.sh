#!/usr/bin/env bash
# Read-only receipt for this experiment family and its two prior jobs.
set -eo pipefail
task_prior_root="/data1/home/sunyiq/precip_dynamic_filter_20260930/run_20261001_222234_hpc_repair1_d27632e6"
test "$(readlink -f "$task_prior_root")" = "$task_prior_root"
test "$(cat "$task_prior_root/submission_receipt.txt")" = "235201"
date -u '+SNAPSHOT_UTC=%Y-%m-%dT%H:%M:%SZ'
printf 'PRIOR_ACCOUNTING_BEGIN\n'
sacct -X -n -P -j 235197,235201 --format=JobID,State,ExitCode,ElapsedRaw,Partition,AllocTRES
printf 'PRIOR_ACCOUNTING_END\n'
test -f "$task_prior_root/pilot/complete.json"
test -f "$task_prior_root/pilot/selection_locked.json"
printf 'PRIOR_COMPLETION_FILES_PRESENT\n'
printf 'OWN_PREVIOUS_JOBS_QUEUE\n'
squeue -h -j 235197,235201 -o '%.18i %.12T %.20R %.12M %.20N'
printf 'PARTITION_GPU_AVAILABILITY\n'
sinfo -p hgpu4 -N -O nodelist,partition,gres:18,gresused:30,cpusstate
printf 'REGISTERED_DATA_ROOT\n'
test -d "/data1/home/sunyiq/neuralhydrology/data/camels_us"
printf 'DATA_ROOT_PRESENT\n'
printf 'DISK_AVAILABLE_BYTES\n'
df -P -B 1 "/data1/home/sunyiq/precip_dynamic_filter_20260930"
