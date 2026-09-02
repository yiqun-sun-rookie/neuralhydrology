#!/bin/bash
# TUKF09-455 v2r6: read-only status of the preparation job. Submits nothing.
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r6_20260902
JID=$(cat "$ROOT/status/preparation_job_id.txt" 2>/dev/null)
echo "PREPARATION_JOB_ID=$JID"
echo "=== SLURM STATE ==="
sacct -j "$JID" -X --format=JobID%10,JobName%26,Partition%8,State%12,ExitCode%8,NodeList%9,Elapsed%10,Start%20,End%20 2>&1
squeue -j "$JID" -h -o "%T %R %M" 2>&1
echo "=== STATUS TREE ==="
ls -la "$ROOT" 2>&1
ls -la "$ROOT/status" 2>&1
echo "=== PREPARATION MARKERS ==="
for f in PREPARATION_FAILED.json staged_training_sources.json preparation_probe.json hpc_technical_admission.json initial_bundle_verification.json; do
  if [ -f "$ROOT/status/$f" ]; then echo "PRESENT $f  $(wc -c < "$ROOT/status/$f") bytes  $(sha256sum "$ROOT/status/$f" | cut -d' ' -f1)"; else echo "ABSENT  $f"; fi
done
echo "=== PRIVATE RUNTIME ==="
if [ -d "$ROOT/runtime_v2r6" ]; then du -sh "$ROOT/runtime_v2r6" 2>&1; find "$ROOT/runtime_v2r6" -maxdepth 1 -mindepth 1 2>&1; else echo "RUNTIME_ABSENT"; fi
ls -d "$ROOT"/runtime_v2r6.pending.* 2>/dev/null || echo "NO_PENDING_RUNTIME"
echo "=== RESULT ROOT INSIDE THE BUNDLE ==="
R="$ROOT/bundle/kalmannet/results/tukf09_455_basin_zero_validation_target_variance_revision_v1"
if [ -d "$R" ]; then ls -la "$R" 2>&1; echo "FILTER_UNITS=$(ls "$R/filter" 2>/dev/null | wc -l)"; else echo "RESULT_ROOT_ABSENT"; fi
echo "=== JOB LOG TAIL ==="
tail -c 2500 "$ROOT/logs/prepare-$JID.out" 2>&1
echo "--- stderr ---"
tail -c 1500 "$ROOT/logs/prepare-$JID.err" 2>&1
echo "TUKF09_455_V2R6_PREPARATION_STATUS_READ_ONLY"
