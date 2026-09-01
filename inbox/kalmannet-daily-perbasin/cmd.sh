#!/usr/bin/env bash
set -u

echo '=== QUERY IDENTITY ==='
date --iso-8601=seconds
hostname
echo 'channel=kalmannet-daily-perbasin sequence=1 purpose=read-only-current-job-and-resource-audit'

echo '=== CURRENT USER QUEUE ==='
squeue -u sunyiq -o '%i|%j|%P|%T|%R|%M|%S|%N'
echo "squeue_exit=$?"

echo '=== CURRENT USER ACTIVE ACCOUNTING ==='
sacct -u sunyiq -S 2026-09-01T00:00:00 -X --state=PENDING,RUNNING,CONFIGURING,COMPLETING --format=JobIDRaw,JobName,Partition,State,ExitCode,Start,Elapsed,NodeList -n -P
echo "active_sacct_exit=$?"

echo '=== JOB 217228 ACCOUNTING ==='
sacct -j 217228 -X --format=JobIDRaw,JobName,Partition,State,ExitCode,Submit,Start,End,Elapsed,NodeList -n -P
echo "job_217228_sacct_exit=$?"

echo '=== NODE STATE NGU201 NGU202 NGU203 ==='
sinfo -N -n ngu201,ngu202,ngu203 -o '%N|%P|%t|%G|%C|%m|%e'
echo "target_node_sinfo_exit=$?"

echo '=== PARTITION STATE ==='
sinfo -o '%P|%a|%l|%D|%t|%G'
echo "partition_sinfo_exit=$?"

echo '=== QUERY COMPLETE: NO SUBMISSION OR SIGNAL COMMAND EXECUTED ==='
