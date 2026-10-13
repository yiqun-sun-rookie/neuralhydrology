#!/bin/bash
set -eo pipefail
root=/data1/home/sunyiq/id25_regional_snowloss_20261013_001
jid=$(cat "$root/job_id.txt")
squeue -h -j "$jid" --start -o '%i|%T|%S|%R'
sprio -j "$jid"
sinfo -h -p hcpu48,hcpu48y -o '%P|%a|%D|%t|%C'
scontrol show job "$jid"
