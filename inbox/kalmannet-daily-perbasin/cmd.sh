#!/usr/bin/env bash
set -o pipefail
readonly OUTPUT_ROOT="/data1/home/sunyiq/kalmannet_daily_camels_coldstart_stress_development_20260924_v1"
readonly JOB_ID="227636"
echo "COLDSTART_STRESS_READ_ONLY_MONITOR_V1"
echo "sequence=196"
echo "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "SQUEUE_BEGIN"
squeue -j "$JOB_ID" -h -o '%i|%j|%T|%P|%R|%M|%l' 2>&1 || echo "SQUEUE_NO_RECORD"
echo "SQUEUE_END"
echo "SACCT_BEGIN"
sacct -j "$JOB_ID" --noheader --parsable2 --format=JobID,JobName,User,Partition,State,ExitCode,Elapsed,Start,End,NodeList 2>&1 || echo "SACCT_READ_FAILED"
echo "SACCT_END"
echo "TOP_FILES_BEGIN"
for name in submission_receipt.json compute_admission.json gate.json termination.json completion.json aggregate.json; do
  path="$OUTPUT_ROOT/$name"
  if [[ -f "$path" && ! -L "$path" ]]; then
    printf '%s|%s|%s\n' "$name" "$(stat -c %s "$path")" "$(sha256sum "$path" | awk '{print $1}')"
  else
    echo "$name|ABSENT"
  fi
done
echo "TOP_FILES_END"
for name in compute_admission.json gate.json termination.json completion.json; do
  path="$OUTPUT_ROOT/$name"
  if [[ -f "$path" && ! -L "$path" && $(stat -c %s "$path") -le 60000 ]]; then
    echo "FILE_BEGIN $name"
    cat "$path"
    echo "FILE_END $name"
  fi
done
for path in "$OUTPUT_ROOT/logs/slurm-$JOB_ID.out" "$OUTPUT_ROOT/logs/slurm-$JOB_ID.err"; do
  if [[ -f "$path" ]]; then
    echo "LOG_BEGIN $(basename "$path") bytes=$(stat -c %s "$path")"
    tail -n 30 "$path"
    echo "LOG_END"
  fi
done
if [[ -f "$OUTPUT_ROOT/completion.json" && -f "$OUTPUT_ROOT/aggregate.json" ]]; then
  size=$(stat -c %s "$OUTPUT_ROOT/aggregate.json")
  if [[ "$size" -le 700000 ]]; then
    echo "AGGREGATE_JSON_BEGIN"
    cat "$OUTPUT_ROOT/aggregate.json"
    echo "AGGREGATE_JSON_END"
  else
    echo "AGGREGATE_TOO_LARGE size=$size"
  fi
fi
echo "MONITOR_COMPLETE"
