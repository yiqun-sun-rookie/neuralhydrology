#!/bin/bash
# ID29 seq=65: compact read-only health snapshot for the complete reproduction matrix.
set -eo pipefail

JOBS=202214,202215,202216,202222,202226,202227,202228,202229,202230

echo "=== SQUEUE COUNTS BY PARENT AND STATE ==="
squeue -h -j "$JOBS" -o '%A|%T' | sort | uniq -c

echo "=== SACCT COUNTS BY PARENT, STATE, AND EXIT CODE ==="
sacct -X -n -P -j "$JOBS" --format=JobIDRaw,State,ExitCode | awk -F'|' '
  NF >= 3 && $1 !~ /\./ {
    parent = $1
    sub(/_.*/, "", parent)
    key = parent "|" $2 "|" $3
    count[key]++
  }
  END {
    for (key in count) print count[key] "|" key
  }
' | sort -t'|' -k2,2n -k3,3

echo "=== AGGREGATION DEPENDENCIES ==="
scontrol show job -o 202229 | sed -n 's/.*Dependency=\([^ ]*\).*/202229|\1/p'
scontrol show job -o 202230 | sed -n 's/.*Dependency=\([^ ]*\).*/202230|\1/p'
