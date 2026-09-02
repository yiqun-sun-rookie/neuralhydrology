#!/usr/bin/env bash
set -eo pipefail
ROOT=/data1/home/sunyiq/id31_hydrologic_dynamic_tokens_20260828/repo
JOB=215879
cd "$ROOT"
echo "=== DT08 SCHEDULER ==="
sacct -j "$JOB" --format=JobID,JobName%24,Partition,State,ExitCode,Elapsed,Start,End,NodeList -n -P || true
echo "=== DT08 MANIFESTS ==="
find "$ROOT/results/31_hydrologic_dynamic_tokens/_invocations" -maxdepth 2 -type f -name run_manifest.json -path "*${JOB}*" -print -exec cat {} \; -exec sha256sum {} \; 2>/dev/null || true
echo "=== DT08 STDERR ==="
STDERR="$ROOT/logs/31_hydrologic_dynamic_tokens/development-${JOB}.err"
if test -f "$STDERR"; then wc -c "$STDERR"; tail -n 200 "$STDERR"; else echo "DT08_STDERR_MISSING $STDERR"; fi
echo "=== DT08 OUTPUTS ==="
find "$ROOT/results/31_hydrologic_dynamic_tokens/DT08" -type f -name output.log -print0 2>/dev/null | while IFS= read -r -d '' f; do echo "DT08_OUTPUT $f"; grep -E 'Epoch [0-9]+ average validation loss|Finished training|Training ended|RuntimeError|Traceback' "$f" | tail -n 80 || true; sha256sum "$f"; done
echo "=== DT08 METRICS ==="
find "$ROOT/results/31_hydrologic_dynamic_tokens/DT08" -type f \( -name validation_metrics.csv -o -name 'model_epoch*.pt' \) -printf '%TY-%Tm-%TdT%TH:%TM:%TS%Tz %s %p\n' 2>/dev/null | sort | tail -n 80
find "$ROOT/results/31_hydrologic_dynamic_tokens/DT08" -type f -path '*/validation/model_epoch030/validation_metrics.csv' -exec sha256sum {} \; 2>/dev/null || true
echo ID31_DT08_AUDIT_COMPLETE