#!/bin/bash
set -euo pipefail
root=/data1/home/sunyiq/id25_regional_regionmean_rds04_20261021_001
date -Is
printf 'OWN_JOB_ID='; cat "$root/job_id.txt"
timeout 30 scontrol -o show job 246090
echo START_ESTIMATE
timeout 30 squeue --start -j 246090 -o '%i|%T|%r|%S|%Q|%R' || true
echo OWN_PRIORITY
timeout 30 sprio -l -j 246090 || true
echo CPU_PARTITIONS
timeout 30 scontrol -o show partition | awk '/PartitionName=hcpu|PartitionName=hcore/'
echo CPU_NODE_CAPACITY
timeout 30 sinfo -h -N -o '%P|%N|%t|%c|%C|%m|%f|%E' | awk -F'|' '$1 ~ /^hcpu|^hcore/'
echo ORIGINAL_SUBMISSION_LEDGER
cat "$root/submissions.tsv"
echo EXISTING_RUNTIME
if test -f "$root/runtime.json"; then cat "$root/runtime.json"; fi
if test -f "$root/output/status.json"; then head -c 3000 "$root/output/status.json"; echo; fi
echo READ_ONLY_SCHEDULING_QUERY_NO_PREFLIGHT_OR_SUBMISSION
