#!/bin/bash
set -uo pipefail

ATTEMPT=/data1/home/sunyiq/autoresearch64/runs/unified_autoresearch/hbv_lite_64_hpc_reproduction_20260810_seq48

echo "=== MAILBOX RUNNER PROCESSES ==="
pgrep -af 'hpc_runner_active' || true

echo "=== ACTIVE UNIFIED AUTORESEARCH SLURM JOBS ==="
squeue -u sunyiq -h -o '%i|%j|%T|%M|%R' | grep -E 'a64|autoresearch' || true

echo "=== RECENT UNIFIED AUTORESEARCH ACCOUNTING ==="
sacct -S 2026-08-10T00:00:00 -X -n -o JobID,JobName%28,State,ExitCode,Elapsed,End | grep -E 'a64|autoresearch' | tail -20 || true

echo "=== LAST VERIFIED JOB ==="
sacct -j 202321 -X --format=JobID%12,JobName%20,NodeList%9,State%14,ExitCode%8,Elapsed%10,End%20

echo "=== LAST VERIFIED EVIDENCE ==="
for path in \
  "$ATTEMPT/evidence/REPRODUCTION_SUMMARY.json" \
  "$ATTEMPT/evidence/MANIFEST.sha256" \
  "$ATTEMPT/candidate_run/CANDIDATE_SUMMARY.json"; do
  if [ -f "$path" ]; then
    stat -c '%n|bytes=%s|mtime=%y' "$path"
  else
    echo "MISSING $path"
  fi
done
if [ -f "$ATTEMPT/evidence/MANIFEST.sha256" ]; then
  (cd "$ATTEMPT" && sha256sum -c evidence/MANIFEST.sha256 >/dev/null)
  echo "manifest_check=ok"
else
  echo "manifest_check=missing"
fi
exit 0
