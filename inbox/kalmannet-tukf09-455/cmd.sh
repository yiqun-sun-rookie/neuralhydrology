#!/bin/bash
# TUKF09-455: read-only status of the v2r14 preparation job. Changes nothing.
set -eo pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r14_20260909
echo "TIME=$(date -Is)"
JOB=$(cat "$ROOT/status/preparation_job_id.txt" 2>/dev/null)
echo "PREPARATION_JOB=$JOB"
sacct -j "$JOB" -o JobID,State,ExitCode,Elapsed,NodeList,MaxRSS -P 2>&1 | head -6
squeue -j "$JOB" -o "%.10i %.9P %.8T %.10M %R" 2>&1 | head -3 || true

echo "=== WHAT THE ROOT HOLDS NOW ==="
ls -la "$ROOT" "$ROOT/status" 2>/dev/null
echo "RUNTIME_FINAL=$(test -d "$ROOT/runtime_v2r14" && echo present || echo absent)"
for d in "$ROOT"/runtime_v2r14.pending.*; do test -e "$d" && echo "PENDING=$(basename "$d") BYTES=$(du -sb "$d" 2>/dev/null | cut -f1)"; done

echo "=== PREPARE STDERR TAIL ==="
tail -n 25 "$ROOT/logs/prepare-$JOB.err" 2>/dev/null | cut -c1-300 || echo "(no stderr yet)"
echo "=== PREPARE STDOUT TAIL ==="
tail -n 12 "$ROOT/logs/prepare-$JOB.out" 2>/dev/null | cut -c1-300 || echo "(no stdout yet)"

echo "=== IF PREPARATION FINISHED, WHAT IT WROTE ==="
for f in initial_bundle_verification.json preparation_probe.json hpc_technical_admission.json staged_training_sources.json PREPARATION_FAILED.json; do
  p="$ROOT/status/$f"
  if [ -f "$p" ]; then echo "--- $f ($(stat -c %s "$p") bytes) ---"; python -X utf8 -c "import json,sys;d=json.load(open(sys.argv[1]));print(json.dumps({k:v for k,v in d.items() if not isinstance(v,(list,dict))},indent=1)[:1400])" "$p" 2>&1 | head -40; fi
done

echo TUKF09_455_V2R14_STATUS_READ_ONLY_DONE
