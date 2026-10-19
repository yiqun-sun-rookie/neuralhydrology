#!/bin/bash
set -eo pipefail
export TZ=UTC
r=/data1/home/sunyiq/knet_camels_hpc_20261012_001/attempts/state_channel_repair_probe_20261019_001
hostname
date -u
printf 'SUBMISSION_STDOUT\n'
cat "$r/submission_stdout.txt"
printf '\nSUBMISSION_JSON\n'
if [ -f "$r/submission.json" ]; then cat "$r/submission.json"; fi
printf '\nOWN_QUEUE\n'
squeue -u sunyiq -n knet_init_probe -h -o '%i|%j|%T|%M|%R'
printf '\nOWN_ACCOUNTING\n'
sacct -u sunyiq --name=knet_init_probe --starttime=2026-10-19T15:10:00 --noheader --parsable2 --format=JobID,JobName,State,ExitCode,ElapsedRaw,NodeList,Start,End
