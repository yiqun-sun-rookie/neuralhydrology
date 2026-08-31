#!/usr/bin/env bash
set -eo pipefail

ROOT=/data1/home/sunyiq/id31_hydrologic_dynamic_tokens_20260828/repo
JOB_ID=216541
PROBE_DIR="$ROOT/results/31_hydrologic_dynamic_tokens/_gpu_resource_probes/slurm${JOB_ID}"
REPORT="$PROBE_DIR/probe_report.json"
STDOUT="$ROOT/logs/31_hydrologic_dynamic_tokens/gpu-probe-${JOB_ID}.out"
STDERR="$ROOT/logs/31_hydrologic_dynamic_tokens/gpu-probe-${JOB_ID}.err"

test -d "$ROOT/.git"
cd "$ROOT"

echo "=== ID31 GPU PROBE ${JOB_ID}: SCHEDULER ==="
squeue -j "$JOB_ID" -o '%.18i %.24j %.2t %.10M %.30R' || true
sacct -j "$JOB_ID" --format=JobID,JobName%24,Partition,State,ExitCode,Elapsed,Start,End,NodeList -n -P || true

echo "=== PROBE REPORT ==="
if test -f "$REPORT"; then
  sha256sum "$REPORT"
  cat "$REPORT"
else
  echo "PROBE_REPORT_NOT_YET_AVAILABLE $REPORT"
fi

echo "=== STDOUT TAIL ==="
if test -f "$STDOUT"; then tail -n 120 "$STDOUT"; else echo "STDOUT_NOT_YET_AVAILABLE $STDOUT"; fi
echo "=== STDERR TAIL ==="
if test -f "$STDERR"; then tail -n 120 "$STDERR"; else echo "STDERR_NOT_YET_AVAILABLE $STDERR"; fi

echo "ID31_GPU_PROBE_STATUS_SNAPSHOT_COMPLETE"
