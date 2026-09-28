#!/usr/bin/env bash
set -eo pipefail
task_root=/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1
sacct -n -P -j 229342 -o JobID,JobName,State,ExitCode,Elapsed,NodeList,MaxRSS
for suffix in out err; do
  task_log="$task_root/logs/saved-statistics-229342.$suffix"
  if [ -f "$task_log" ]; then echo "DIAGNOSTIC_LOG_$suffix"; tail -n 35 "$task_log"; fi
done
task_report="$task_root/saved_stats_diagnostic_001/diagnostic.json"
if [ -f "$task_report" ]; then
  echo "DIAGNOSTIC_SHA256=$(sha256sum "$task_report" | cut -d' ' -f1)"
  echo BEGIN_SAVED_STATISTICS_DIAGNOSTIC_JSON
  cat "$task_report"
  echo
  echo END_SAVED_STATISTICS_DIAGNOSTIC_JSON
fi
task_failure="$task_root/saved_stats_diagnostic_001/failure.json"
if [ -f "$task_failure" ]; then echo DIAGNOSTIC_FAILURE; cat "$task_failure"; fi
find "$task_root/adaptive_preflight_v1/adaptive_comparison/runs" -path '*__formal_attempt01/physical_plain_*.py' -type f -exec sha256sum {} \;
