#!/usr/bin/env bash
set -eo pipefail
readonly SEQUENCE=185
readonly JOB_ID=227131
readonly OUTPUT_ROOT="/data1/home/sunyiq/kalmannet_daily_camels_stability_diagnosis_development_20260921_v1"

echo "DIAG_OBSERVE_V1"
echo "sequence=$SEQUENCE"
echo "timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "host=$(hostname)"
echo "QUEUE_BEGIN"
squeue -h -j "$JOB_ID" -o '%i|%j|%T|%P|%N|%R|%M|%l' || true
echo "QUEUE_END"
echo "ACCOUNTING_BEGIN"
sacct -X -n -P -j "$JOB_ID" --format=JobIDRaw,JobName,State,ExitCode,Elapsed,Timelimit,NodeList || true
echo "ACCOUNTING_END"
echo "FILE_COUNT=$(find "$OUTPUT_ROOT" -type f -print | wc -l)"
if [[ -f "$OUTPUT_ROOT/failure.json" ]]; then
  echo "FAILURE_BEGIN"
  cat "$OUTPUT_ROOT/failure.json"
  echo "FAILURE_END"
fi
if [[ -f "$OUTPUT_ROOT/success.json" ]]; then
  echo "SUCCESS_BEGIN"
  cat "$OUTPUT_ROOT/success.json"
  echo "SUCCESS_END"
  echo "REPORT_BEGIN"
  cat "$OUTPUT_ROOT/report.md"
  echo "REPORT_END"
  echo "AGGREGATE_BEGIN"
  cat "$OUTPUT_ROOT/aggregate_summary.json"
  echo "AGGREGATE_END"
else
  echo "STDOUT_TAIL_BEGIN"
  tail -n 80 "$OUTPUT_ROOT"/logs/slurm-"$JOB_ID".out 2>/dev/null || true
  echo "STDOUT_TAIL_END"
  echo "STDERR_TAIL_BEGIN"
  tail -n 80 "$OUTPUT_ROOT"/logs/slurm-"$JOB_ID".err 2>/dev/null || true
  echo "STDERR_TAIL_END"
fi
