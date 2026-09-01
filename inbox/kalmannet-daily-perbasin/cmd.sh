#!/usr/bin/env bash
set -u

REMOTE_ROOT="/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901"
EXECUTION_ID="DAILY_CAMELS_KNET_PER_BASIN_PILOT_A800_PROBE2_SEQ3"
PROBE_DIRECTORY="${REMOTE_ROOT}/probes/${EXECUTION_ID}"
JOB_ID="217245"

echo '=== QUERY IDENTITY ==='
date --iso-8601=seconds
hostname
echo 'channel=kalmannet-daily-perbasin sequence=4 purpose=read-only-probe-terminal-check'

echo '=== SLURM QUEUE ==='
squeue -j "${JOB_ID}" -o '%i|%j|%P|%T|%R|%M|%S|%N'
echo "squeue_exit=$?"

echo '=== SLURM ACCOUNTING ==='
sacct -j "${JOB_ID}" -X --format=JobIDRaw,JobName,Partition,State,ExitCode,Submit,Start,End,Elapsed,NodeList -n -P
echo "sacct_exit=$?"

echo '=== SUBMISSION RECEIPT ==='
if [[ -f "${PROBE_DIRECTORY}/submission_receipt.txt" ]]; then
  sha256sum "${PROBE_DIRECTORY}/submission_receipt.txt"
  cat "${PROBE_DIRECTORY}/submission_receipt.txt"
else
  echo 'submission_receipt_missing'
fi

echo '=== PROBE RECEIPT ==='
if [[ -f "${PROBE_DIRECTORY}/probe_receipt.json" ]]; then
  sha256sum "${PROBE_DIRECTORY}/probe_receipt.json"
  cat "${PROBE_DIRECTORY}/probe_receipt.json"
else
  echo 'probe_receipt_missing'
fi

echo '=== PROBE STANDARD OUTPUT ==='
if [[ -f "${PROBE_DIRECTORY}/slurm-${JOB_ID}.out" ]]; then
  sha256sum "${PROBE_DIRECTORY}/slurm-${JOB_ID}.out"
  cat "${PROBE_DIRECTORY}/slurm-${JOB_ID}.out"
else
  echo 'probe_stdout_missing'
fi

echo '=== PROBE STANDARD ERROR ==='
if [[ -f "${PROBE_DIRECTORY}/slurm-${JOB_ID}.err" ]]; then
  sha256sum "${PROBE_DIRECTORY}/slurm-${JOB_ID}.err"
  cat "${PROBE_DIRECTORY}/slurm-${JOB_ID}.err"
else
  echo 'probe_stderr_missing'
fi

echo '=== QUERY COMPLETE: NO SUBMISSION, TRAINING, FILE MODIFICATION, OR SIGNAL ==='
