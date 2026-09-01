#!/usr/bin/env bash
set -euo pipefail

REMOTE_ROOT="/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901"
EXECUTION_ID="DAILY_CAMELS_KNET_PER_BASIN_PILOT_A800_PROBE3_SEQ5"
PROBE_DIRECTORY="${REMOTE_ROOT}/probes/${EXECUTION_ID}"
JOB_ID="217269"
JOB_NAME="kdpp-a800-probe-s5"

echo '=== READ-ONLY TERMINAL PROBE QUERY ==='
date --iso-8601=seconds
hostname
echo 'channel=kalmannet-daily-perbasin sequence=6 purpose=read-only-terminal-probe-query'
echo 'signals_sent=0 submissions_created=0 files_modified=0'

echo '=== SQUEUE ==='
squeue -j "${JOB_ID}" -o '%i|%j|%P|%T|%R|%M|%S|%N' || true

echo '=== SACCT ==='
sacct -j "${JOB_ID}" -X \
  --format=JobIDRaw,JobName,Partition,State,ExitCode,Elapsed,Start,End,NodeList,AllocTRES \
  -n -P || true

echo '=== EXACT NAME COUNTS ==='
squeue -h -u sunyiq -o '%i|%j|%T|%N' | \
  awk -F'|' -v name="${JOB_NAME}" '$2 == name {count++} END {print "active_exact_name=" count+0}'
sacct -u sunyiq -S 2026-09-01T00:00:00 -X --format=JobIDRaw,JobName,State -n -P | \
  awk -F'|' -v name="${JOB_NAME}" '$2 == name {count++} END {print "historical_exact_name=" count+0}'

for member in submission_receipt.txt "slurm-${JOB_ID}.out" "slurm-${JOB_ID}.err" probe_receipt.json; do
  path="${PROBE_DIRECTORY}/${member}"
  echo "=== ${member} ==="
  if [[ -f "${path}" ]]; then
    sha256sum "${path}"
    cat "${path}"
  else
    echo 'MISSING'
  fi
done

echo '=== CURRENT USER JOBS ==='
squeue -u sunyiq -o '%i|%j|%P|%T|%R|%M|%S|%N'
echo '=== QUERY COMPLETE: READ ONLY, NO TRAINING OR SIGNAL ==='
