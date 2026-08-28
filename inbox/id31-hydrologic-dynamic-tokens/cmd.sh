#!/usr/bin/env bash
set -eo pipefail

ROOT=/data1/home/sunyiq/id31_hydrologic_dynamic_tokens_20260828/repo
JOB_ID=215876
REPORT="$ROOT/results/31_hydrologic_dynamic_tokens/_gpu_resource_probes/slurm${JOB_ID}/probe_report.json"
STDOUT="$ROOT/logs/31_hydrologic_dynamic_tokens/gpu-probe-${JOB_ID}.out"
STDERR="$ROOT/logs/31_hydrologic_dynamic_tokens/gpu-probe-${JOB_ID}.err"

test -d "$ROOT/.git"
echo "=== SLURM STATUS ==="
squeue -j "$JOB_ID" -o '%.18i %.12P %.30j %.2t %.10M %.20R' || true
sacct -j "$JOB_ID" --format=JobID,JobName%30,Partition,State,ExitCode,Elapsed,NodeList -n -P || true

echo "=== PROBE REPORT ==="
if [ -f "$REPORT" ]; then
  sha256sum "$REPORT"
  cat "$REPORT"
else
  echo "PROBE_REPORT_PENDING"
fi

echo "=== STDOUT TAIL ==="
if [ -f "$STDOUT" ]; then tail -n 80 "$STDOUT"; else echo "STDOUT_PENDING"; fi
echo "=== STDERR TAIL ==="
if [ -f "$STDERR" ]; then tail -n 80 "$STDERR"; else echo "STDERR_PENDING"; fi
