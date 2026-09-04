#!/bin/bash
# TUKF09-455 v2r7 preparation status. Read-only, submits nothing.
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r7_20260904
JID=$(cat "$ROOT/status/preparation_job_id.txt" 2>/dev/null)
echo "TIME=$(date -Is)"
echo "PREPARATION_JOB_ID=$JID"
sacct -j "$JID" -X --format=JobID%10,State%12,ExitCode%8,NodeList%9,Elapsed%10,Start%20,End%20 2>&1
squeue -j "$JID" -h -o "QUEUE %T | %R | %M" 2>&1
sinfo -p hgpu8 -o "%.10P %.6a %.6D %.8t %.24N %.20C" 2>&1
echo "=== MARKERS ==="
for f in PREPARATION_FAILED.json initial_bundle_verification.json staged_training_sources.json preparation_probe.json hpc_technical_admission.json training_job_id.txt; do
  if [ -f "$ROOT/status/$f" ]; then echo "PRESENT $f  $(sha256sum "$ROOT/status/$f" | cut -d' ' -f1)"; else echo "ABSENT  $f"; fi
done
if [ -d "$ROOT/runtime_v2r7" ]; then echo "PRIVATE_RUNTIME_PRESENT $(du -sh "$ROOT/runtime_v2r7" | cut -f1)"; else echo "PRIVATE_RUNTIME_ABSENT"; fi
ls -d "$ROOT"/runtime_v2r7.pending.* 2>/dev/null || echo "NO_PENDING_RUNTIME"
RR="$ROOT/bundle/kalmannet/results/tukf09_455_basin_zero_validation_target_variance_revision_v1"
if [ -d "$RR" ]; then echo "FILTER_UNITS=$(ls "$RR/filter" 2>/dev/null | wc -l)"; echo "NEURAL_UNITS=$(ls "$RR/neural" 2>/dev/null | wc -l)"; else echo "RESULT_ROOT_ABSENT"; fi
echo "=== LOG TAIL ==="
tail -c 2500 "$ROOT/logs/prepare-$JID.out" 2>&1
tail -c 900 "$ROOT/logs/prepare-$JID.err" 2>&1
echo "TUKF09_455_V2R7_PREPARATION_STATUS_READ_ONLY"
