#!/bin/bash
# TUKF09-455: read back the graphics-process probe capture.
# Read-only. Submits nothing. Touches no frozen experiment root.

set -o pipefail

DIAG_ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_pmon_probe_diagnostics_20260902
V2R5=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r5_20260901
JID=$(cat "$DIAG_ROOT/job/job_id.txt" 2>/dev/null)
echo "PROBE_JOB_ID=$JID"

echo "=== JOB STATE ==="
sacct -j "$JID" -X --format=JobID%10,JobName%24,Partition%8,State%14,ExitCode%8,NodeList%10,Elapsed%10,Start%20,End%20 2>&1
echo "--- still queued or running? ---"
squeue -j "$JID" -h -o "%T %R" 2>&1

echo "=== JOB STANDARD OUTPUT ==="
OUT="$DIAG_ROOT/logs/pmon-probe-$JID.out"
if [ -f "$OUT" ]; then
  ls -l "$OUT"
  sha256sum "$OUT"
  echo "--- begin ---"
  cat "$OUT"
  echo "--- end ---"
else
  echo "ABSENT $OUT"
fi

echo "=== JOB STANDARD ERROR ==="
ERR="$DIAG_ROOT/logs/pmon-probe-$JID.err"
if [ -f "$ERR" ]; then
  ls -l "$ERR"
  sha256sum "$ERR"
  echo "--- begin ---"
  cat "$ERR"
  echo "--- end ---"
else
  echo "ABSENT $ERR"
fi

echo "=== CAPTURE DIRECTORY ==="
ls -lR "$DIAG_ROOT/capture_$JID" 2>&1

echo "=== FROZEN EVIDENCE STILL UNCHANGED ==="
echo "JOB_ID_FILE_CONTENT=$(cat "$V2R5/status/training_job_id.txt" 2>&1)"
sha256sum "$V2R5/logs/training-217939.out" "$V2R5/logs/training-217939.err" 2>&1

echo "TUKF09_455_PMON_PROBE_READBACK_COMPLETED"
