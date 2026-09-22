#!/usr/bin/env bash
set -eo pipefail
readonly JOB_ID=227265
readonly OUTPUT_ROOT="/data1/home/sunyiq/kalmannet_daily_camels_state_update_control_20260921_v1"
echo "FIXED_CONTROL_READ_ONLY_MONITOR_V1"
echo "sequence=189"
echo "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "job_id=$JOB_ID"
echo "SQUEUE_BEGIN"
squeue -j "$JOB_ID" -h -o '%i|%j|%u|%T|%P|%R|%M' || true
echo "SQUEUE_END"
echo "SACCT_BEGIN"
sacct -j "$JOB_ID" --noheader --parsable2 --format=JobID,JobName,User,Partition,State,ExitCode,Elapsed,Start,End || true
echo "SACCT_END"
for name in submission_receipt.json compute_admission.json completion.json; do
  file="$OUTPUT_ROOT/$name"
  if [[ -f "$file" ]]; then
    echo "FILE_BEGIN $name"
    wc -c < "$file"
    sha256sum "$file"
    cat "$file"
    echo "FILE_END $name"
  else
    echo "FILE_ABSENT $name"
  fi
done
for name in slurm-227265.out slurm-227265.err; do
  file="$OUTPUT_ROOT/logs/$name"
  if [[ -f "$file" ]]; then
    echo "LOG_BEGIN $name"
    wc -c < "$file"
    tail -n 20 "$file"
    echo "LOG_END $name"
  else
    echo "LOG_ABSENT $name"
  fi
done
if [[ -f "$OUTPUT_ROOT/aggregate.json" ]]; then
  echo "AGGREGATE_PRESENT"
  wc -c < "$OUTPUT_ROOT/aggregate.json"
  sha256sum "$OUTPUT_ROOT/aggregate.json"
else
  echo "AGGREGATE_ABSENT"
fi
