#!/usr/bin/env bash
set -o pipefail
readonly OUTPUT_ROOT="/data1/home/sunyiq/kalmannet_daily_camels_slz_survey_development_20260928_v1"
readonly JOB_ID="231448"
echo "SLZ_SURVEY_READ_ONLY_MONITOR_V1"
echo "sequence=226"
echo "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "SQUEUE_BEGIN"
squeue -j "$JOB_ID" -h -o '%i|%j|%T|%P|%R|%M|%l' 2>&1 || echo "SQUEUE_NO_RECORD"
echo "SQUEUE_END"
echo "SACCT_BEGIN"
sacct -j "$JOB_ID" --noheader --parsable2 --format=JobID,JobName,User,Partition,State,ExitCode,Elapsed,Start,End,NodeList 2>&1 || echo "SACCT_READ_FAILED"
echo "SACCT_END"
echo "TOP_FILES_BEGIN"
for name in submission_receipt.json compute_admission.json termination.json completion.json aggregate.json; do
  path="$OUTPUT_ROOT/$name"
  if [[ -f "$path" && ! -L "$path" ]]; then
    printf '%s|%s|%s\n' "$name" "$(stat -c %s "$path")" "$(sha256sum "$path" | awk '{print $1}')"
  else
    echo "$name|ABSENT"
  fi
done
echo "TOP_FILES_END"
if [[ -d "$OUTPUT_ROOT/basins" ]]; then
  echo "completed_basin_records=$(find "$OUTPUT_ROOT/basins" -mindepth 2 -maxdepth 2 -type f -name records.json | wc -l)"
fi
for name in compute_admission.json termination.json completion.json; do
  path="$OUTPUT_ROOT/$name"
  if [[ -f "$path" && ! -L "$path" && $(stat -c %s "$path") -le 60000 ]]; then
    echo "FILE_BEGIN $name"
    cat "$path"
    echo "FILE_END $name"
  fi
done
for path in "$OUTPUT_ROOT/logs/slurm-$JOB_ID.out" "$OUTPUT_ROOT/logs/slurm-$JOB_ID.err"; do
  if [[ -f "$path" && ! -L "$path" ]]; then
    echo "LOG_BEGIN $(basename "$path") bytes=$(stat -c %s "$path")"
    tail -n 40 "$path"
    echo "LOG_END"
  fi
done
if [[ -f "$OUTPUT_ROOT/completion.json" && -f "$OUTPUT_ROOT/aggregate.json" && ! -L "$OUTPUT_ROOT/aggregate.json" ]]; then
  size=$(stat -c %s "$OUTPUT_ROOT/aggregate.json")
  encoded=$(gzip -9 -c "$OUTPUT_ROOT/aggregate.json" | base64 --wrap=0 | wc -c)
  if [[ "$encoded" -le 600000 ]]; then
    echo "AGGREGATE_GZIP_BASE64_BEGIN bytes=$size"
    gzip -9 -c "$OUTPUT_ROOT/aggregate.json" | base64 --wrap=0
    echo
    echo "AGGREGATE_GZIP_BASE64_END"
  else
    echo "AGGREGATE_ENCODED_TOO_LARGE size=$size encoded=$encoded"
  fi
fi
echo "MONITOR_COMPLETE"
