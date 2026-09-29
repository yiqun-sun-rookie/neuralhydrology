#!/bin/bash
# precip-selfrule-v05 seq=23: read Slurm timeout and termination-grace settings.
set -eo pipefail

date "+wallclock %F %T %z"
scontrol show config | awk -F= '
  /KillWait|OverTimeLimit/ {
    key=$1; value=$2;
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", key);
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", value);
    print key "=" value
  }
'
