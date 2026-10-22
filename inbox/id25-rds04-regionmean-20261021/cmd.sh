#!/bin/bash
set -uo pipefail
date -Is
root=/data1/home/sunyiq/id25_regional_regionmean_rds04_20261021_001
printf 'JOB_DETAIL\n'
timeout 30 scontrol -dd show job 246090
printf 'CONFIG_SCHEDULER\n'
timeout 30 scontrol show config | awk '$1 ~ /^(SelectType|SelectTypeParameters|SchedulerType|SchedulerParameters|PreemptType|PreemptMode|PriorityType|PriorityFlags|TaskPlugin|ProctrackType|DefMemPerCPU|DefMemPerNode)$/ {print}'
printf 'CPU_PARTITIONS\n'
timeout 30 scontrol -o show partition hcpu48
timeout 30 scontrol -o show partition hcpu48y
printf 'NODE_DETAIL\n'
timeout 30 scontrol -o show node 'icn[270-281]'
printf 'RESERVATIONS\n'
timeout 30 scontrol -o show reservation
printf 'CPU_Y_QUEUE\n'
timeout 30 squeue -h -p hcpu48y -t RUNNING,PENDING --sort=-p -o '%i|%u|%T|%C|%D|%l|%S|%r|%R|%Q'
printf 'START_ESTIMATE\n'
timeout 30 squeue --start -j 246090 -o '%i|%T|%r|%S|%Q|%R'
printf 'OWN_TRAINING_STATUS\n'
for rel in job_id.txt submissions.tsv runtime.json output/status.json; do echo "FILE=$rel"; if test -f "$root/$rel"; then cat "$root/$rel"; fi; done
if test -f "$root/output/metrics.jsonl"; then tail -n 2 "$root/output/metrics.jsonl"; fi
printf 'READ_ONLY_DIAGNOSIS_FINISHED\n'
