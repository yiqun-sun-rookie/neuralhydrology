#!/bin/bash
set -eo pipefail

JID=202243
ATTEMPT=/data1/home/sunyiq/autoresearch64/runs/unified_autoresearch/hbv_lite_8_hpc_smoke_20260810_seq36

echo "=== JOB STATE ==="
squeue -j "$JID" -h -o 'job=%i state=%T elapsed=%M node=%N'
sacct -j "$JID" -X --format=JobID%12,JobName%20,State%14,ExitCode%8,Elapsed%10

echo "=== EXACT JOB LOGS ==="
tail -80 "outbox/slurm_${JID}.out" 2>/dev/null || true
tail -80 "outbox/slurm_${JID}.err" 2>/dev/null || true

echo "=== EVIDENCE STATUS ==="
for path in \
  "$ATTEMPT/candidate_run/CANDIDATE_SUMMARY.json" \
  "$ATTEMPT/evidence/SMOKE_SUMMARY.json" \
  "$ATTEMPT/evidence/MANIFEST.sha256"
do
  if [ -f "$path" ]; then echo "EXISTS $path"; else echo "MISSING $path"; fi
done
