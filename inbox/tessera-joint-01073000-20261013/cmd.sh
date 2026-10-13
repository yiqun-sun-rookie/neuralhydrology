#!/bin/bash
set -eo pipefail
ROOT=/data1/home/sunyiq/tessera_joint_01073000_20261013_001
JID=$(cat "$ROOT/job_id.txt")
case "$JID" in ''|*[!0-9]*) echo INVALID_OWN_JOB_ID; exit 1;; esac
date -u
echo "EXPERIMENT_ROOT=$ROOT JOB_ID=$JID"
squeue -j "$JID" -h -o '%i %j %T %M %R' || true
sacct -j "$JID" --format=JobID,JobName,State,ExitCode,Elapsed,MaxRSS
scontrol show job "$JID" || true
for file in "$ROOT/logs/abc-$JID.out" "$ROOT/logs/abc-$JID.err"; do
  if [ -f "$file" ]; then echo "LOG=$file"; tail -n 35 "$file"; fi
done
if [ -f "$ROOT/results/report.json" ]; then
  echo REPORT_JSON_BEGIN
  cat "$ROOT/results/report.json"
  echo REPORT_JSON_END
  if grep -q 'REAL_TEMPORAL_PILOT_COMPLETE_NO_GENERALIZATION_CLAIM' "$ROOT/results/report.json"; then
    cd "$ROOT"
    tar -czf "summary-$JID.tar.gz" results/report.json results/config_snapshot.json results/environment.json results/registry.csv results/A/*.json results/B/*.json results/C/*.json results/A/test_predictions.* results/B/test_predictions.* results/C/test_predictions.*
    echo SUMMARY_ARCHIVE_BASE64_BEGIN
    base64 -w 0 "summary-$JID.tar.gz"
    echo
    echo SUMMARY_ARCHIVE_BASE64_END
  fi
fi
