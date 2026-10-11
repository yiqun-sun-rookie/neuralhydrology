#!/bin/bash
set -euo pipefail
printf 'WEATHER_STATUS_COLLECTION_UTC=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
base=/data1/home/sunyiq/us_nonnegative_repair_execution_20261010_001
prep=$base/preparation_v1
[[ -d "$base" && ! -L "$base" && -d "$prep" && ! -L "$prep" ]]
[[ -f "$prep/OWN_WEATHER_PREPARATION_JOB_ID.txt" && ! -L "$prep/OWN_WEATHER_PREPARATION_JOB_ID.txt" ]]
job=$(cat "$prep/OWN_WEATHER_PREPARATION_JOB_ID.txt")
[[ "$job" == 240023 ]]
printf 'OWN_WEATHER_PREPARATION_JOB_ID=%s\n' "$job"
squeue -h -j "$job" -o '%i|%j|%T|%R' || true
sacct -X -j "$job" --noheader --parsable2 --format=JobIDRaw,JobName,State,ExitCode,Elapsed,AllocTRES,ReqTRES || true
cd "$prep"
[[ "$PWD" == "$prep" && "$(pwd -P)" == "$prep" ]]
python=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python
[[ -x "$python" ]]
if [[ -f "$prep/logs/weather-${job}.err" && ! -L "$prep/logs/weather-${job}.err" ]]; then
    printf 'OWN_WEATHER_PREPARATION_STDERR_TAIL\n'
    tail -c 32768 "$prep/logs/weather-${job}.err"
fi
"$python" -B -X utf8 src/print_weather_review_receipt.py
printf 'OWN_WEATHER_READONLY_COLLECTION_DONE\n'
