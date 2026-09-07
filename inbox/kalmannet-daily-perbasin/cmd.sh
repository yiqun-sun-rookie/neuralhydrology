#!/usr/bin/env bash
set -uo pipefail
sequence=36
echo "channel=kalmannet-daily-perbasin sequence=${sequence} purpose=task6-readonly-failed-allocation-and-maintenance"
date --iso-8601=seconds
hostname
echo 'training_submissions=0 runtime_submissions=0 task_file_writes=0 signals_sent=0 formal_evaluation_access=0'
echo '=== EXACT FAILED RUNTIME JOB ACCOUNTING ==='
sacct -X -n -P -j 223507 --format=JobIDRaw,JobName%80,State,ExitCode,Submit,Eligible,Start,End,Elapsed,NodeList,AllocTRES%120,Reason%150
account_exit=$?
echo "sacct_exit_code=$account_exit"
echo '=== EXACT JOB CONTROLLER RECORD ==='
scontrol show job 223507
echo "scontrol_job_exit_code=$?"
echo '=== REGISTERED NODE RECORD ==='
scontrol show node ngu202
node_exit=$?
echo "scontrol_node_exit_code=$node_exit"
echo '=== REGISTERED NODE STATE AND REASON ==='
sinfo -N -n ngu202 -o '%N|%P|%T|%G|%C|%m|%E'
sinfo -R -n ngu202
echo '=== CURRENT RELATED JOBS ==='
squeue -h -u "$(id -un)" -o '%i|%200j|%T|%N|%R' | awk -F'|' '$2 ~ /(kdpp|DAILY_CAMELS_KNET_PER_BASIN|daily.camels.*per.basin|kalmannet.daily.perbasin)/'
echo '=== FAILED REQUEST OUTPUT METADATA ONLY ==='
ROOT=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901
AUDIT="$ROOT/runtime_gate_audits/V2_TASK6_SEQ35"
if [[ -d "$AUDIT" && ! -L "$AUDIT" ]]; then
    find "$AUDIT" -mindepth 1 -maxdepth 2 -printf '%y|%P|%s\n' | sort
fi
[[ "$account_exit" == 0 && "$node_exit" == 0 ]] || exit 93
echo 'READONLY_JOB_AND_MAINTENANCE_QUERY_COMPLETE'
