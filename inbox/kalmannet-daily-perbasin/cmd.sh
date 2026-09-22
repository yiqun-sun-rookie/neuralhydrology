#!/usr/bin/env bash
set -eo pipefail
readonly OUTPUT_ROOT="/data1/home/sunyiq/kalmannet_daily_camels_state_update_control_20260921_v1"
readonly EXPECTED_SHA="9e801d2e858fcae945ba783a123f1fd22f3fbc64911d341a86ca0b05292016e4"
echo "FIXED_CONTROL_AGGREGATE_READ_ONLY_V1"
echo "sequence=190"
echo "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '%s  %s\n' "$EXPECTED_SHA" "$OUTPUT_ROOT/aggregate.json" | sha256sum --check --strict
echo "AGGREGATE_JSON_BEGIN"
cat "$OUTPUT_ROOT/aggregate.json"
echo "AGGREGATE_JSON_END"
echo "SACCT_BEGIN"
sacct -j 227265 --noheader --parsable2 --format=JobID,JobName,User,Partition,State,ExitCode,Elapsed
echo "SACCT_END"
