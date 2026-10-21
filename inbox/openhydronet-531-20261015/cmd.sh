#!/bin/bash
set -o pipefail
# read-only: result of the smoke job that went through the shared template
ROOT=/data1/home/sunyiq/openhydronet_531_20261015
date --iso-8601=seconds
sacct -X -n -P -j 245855 --format=JobID,JobName,State,ExitCode,Elapsed,NodeList
F="$ROOT/logs/ohn_shared_smoke-245855.out"
[ -f "$F" ] && { grep -aE "^host=|^torch|ohn|run_dir=|^done=" "$F" | cut -c1-160 | head -8; tr '\r' '\n' < "$F" | grep -aE "median=|Epoch [0-9] average" | cut -c1-200 | tail -6; }
grep -aE "Traceback|Error" "$F" "${F%.out}.err" 2>/dev/null | head -3 | cut -c1-200
exit 0
