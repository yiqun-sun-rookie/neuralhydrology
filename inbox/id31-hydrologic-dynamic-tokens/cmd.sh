#!/usr/bin/env bash
set -eo pipefail

ROOT=/data1/home/sunyiq/id31_hydrologic_dynamic_tokens_20260828/repo
ALTERNATIVE_JOB_ID=216548
FALLBACK_JOB_ID=216541

test -d "$ROOT/.git"
cd "$ROOT"

for JOB_ID in "$ALTERNATIVE_JOB_ID" "$FALLBACK_JOB_ID"; do
  PROBE_DIR="results/31_hydrologic_dynamic_tokens/_gpu_resource_probes/slurm${JOB_ID}"
  REPORT="$PROBE_DIR/probe_report.json"
  STDOUT="logs/31_hydrologic_dynamic_tokens/gpu-probe-${JOB_ID}.out"
  STDERR="logs/31_hydrologic_dynamic_tokens/gpu-probe-${JOB_ID}.err"

  echo "=== GPU PROBE ${JOB_ID}: SCHEDULER ==="
  squeue -j "$JOB_ID" -o '%.18i %.24j %.12P %.2t %.10M %.10l %.30R' || true
  sacct -j "$JOB_ID" --format=JobID,JobName%24,Partition,State,ExitCode,Elapsed,Start,End,NodeList -n -P || true

  echo "=== GPU PROBE ${JOB_ID}: REPORT ==="
  if test -f "$REPORT"; then sha256sum "$REPORT"; cat "$REPORT"; else echo "REPORT_PENDING $REPORT"; fi
  echo "=== GPU PROBE ${JOB_ID}: STDOUT TAIL ==="
  if test -f "$STDOUT"; then tail -n 160 "$STDOUT"; else echo "STDOUT_PENDING $STDOUT"; fi
  echo "=== GPU PROBE ${JOB_ID}: STDERR TAIL ==="
  if test -f "$STDERR"; then tail -n 160 "$STDERR"; else echo "STDERR_PENDING $STDERR"; fi
done

echo "ID31_DUAL_GPU_PROBE_STATUS_COMPLETE"
