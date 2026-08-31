#!/usr/bin/env bash
set -eo pipefail

ROOT=/data1/home/sunyiq/id31_hydrologic_dynamic_tokens_20260828/repo
JOB_ID=216549
RUN_ID="id31_DL01_s100_slurm${JOB_ID}"
RUN_ROOT="$ROOT/results/31_hydrologic_dynamic_tokens/DL01"
MANIFEST="$ROOT/results/31_hydrologic_dynamic_tokens/_invocations/${RUN_ID}/run_manifest.json"
STDOUT="$ROOT/logs/31_hydrologic_dynamic_tokens/development-${JOB_ID}.out"
STDERR="$ROOT/logs/31_hydrologic_dynamic_tokens/development-${JOB_ID}.err"

test -d "$ROOT/.git"
cd "$ROOT"

echo "=== ID31 DL01 CURRENT SCHEDULER STATUS ==="
date -Is
squeue -j "$JOB_ID" -o '%.18i %.24j %.12P %.2t %.12M %.12l %.30R' || true
sacct -j "$JOB_ID" --format=JobID,JobName%24,Partition,State,ExitCode,Elapsed,Start,End,NodeList -n -P || true

echo "=== RUN MANIFEST ==="
if test -f "$MANIFEST"; then sha256sum "$MANIFEST"; cat "$MANIFEST"; else echo "RUN_MANIFEST_MISSING $MANIFEST"; fi

echo "=== DL01 RUN DIRECTORIES ==="
if test -d "$RUN_ROOT"; then
  find "$RUN_ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%TY-%Tm-%TdT%TH:%TM:%TS%Tz %p\n' | sort
else
  echo "RUN_ROOT_MISSING $RUN_ROOT"
fi

LATEST_OUTPUT=$(find "$RUN_ROOT" -type f -name output.log -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n 1 | cut -d' ' -f2-)
echo "=== ACTIVE TRAINING OUTPUT ==="
if test -n "$LATEST_OUTPUT" && test -f "$LATEST_OUTPUT"; then
  echo "ACTIVE_OUTPUT $LATEST_OUTPUT"
  sha256sum "$LATEST_OUTPUT"
  echo "--- PROGRESS AND VALIDATION LINES ---"
  tr '\r' '\n' < "$LATEST_OUTPUT" \
    | grep -E 'Epoch|average loss|avg_loss|Validat|median|NSE|dynamic_token|Finished training|Training ended' \
    | tail -n 180 || true
  echo "--- OUTPUT TAIL ---"
  tail -n 160 "$LATEST_OUTPUT"
else
  echo "ACTIVE_OUTPUT_MISSING"
fi

echo "=== METRIC AND CHECKPOINT ARTIFACTS ==="
if test -d "$RUN_ROOT"; then
  find "$RUN_ROOT" -type f \
    \( -name 'epoch*_metrics.json' -o -name 'validation_metrics.csv' -o -name 'model_epoch*.pt' \
       -o -name 'validation_results.p' \) \
    -printf '%TY-%Tm-%TdT%TH:%TM:%TS%Tz %s %p\n' | sort | tail -n 120
  while IFS= read -r METRICS; do
    echo "METRICS_FILE $METRICS"
    sha256sum "$METRICS"
    cat "$METRICS"
  done < <(find "$RUN_ROOT" -type f -name 'epoch*_metrics.json' | sort)
fi

echo "=== SLURM STDOUT TAIL ==="
if test -f "$STDOUT"; then tail -n 180 "$STDOUT"; else echo "STDOUT_MISSING $STDOUT"; fi
echo "=== SLURM STDERR TAIL ==="
if test -f "$STDERR"; then tail -n 180 "$STDERR"; else echo "STDERR_MISSING $STDERR"; fi

echo "ID31_DL01_CURRENT_PROGRESS_COMPLETE"
