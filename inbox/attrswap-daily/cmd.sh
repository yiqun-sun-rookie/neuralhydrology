#!/bin/bash
# forcing-swap status -- READ-ONLY. Queue, accounting, conversion report, medians, latest epoch, any error.
set -o pipefail
date "+wallclock %F %T %z"
R=/data1/home/sunyiq/forcing_swap_daily_2026_09
echo "=== A. QUEUE ==="
squeue -u "$USER" -o '%.11i %.22j %.9T %.10M %.9N %.20E' 2>&1 | grep -Ei 'fswap|JOBID' || echo '  (none queued)'
echo "=== B. ACCOUNTING ==="
ids=$(tr '\n' ',' < "$R/logs/job_ids.txt" | sed 's/,$//')
sacct -j "$ids" -X --format=JobID%9,JobName%20,State%12,ExitCode%8,Elapsed%10,NodeList%9 2>&1
echo "=== C. GATE + CONVERSION REPORT ==="
cat "$R/logs/gate.txt" 2>/dev/null || echo "  (gate marker absent)"
cat "$R/logs/convert_verify.json" 2>/dev/null || echo "  (conversion report absent)"
echo "=== D. MEDIANS ==="
for f in "$R"/logs/*.public_median.txt; do [ -f "$f" ] && echo "  $(basename $f .public_median.txt): $(cat $f)"; done
echo "medians present: $(ls "$R"/logs/*.public_median.txt 2>/dev/null | wc -l)/9"
echo "=== E. LATEST EPOCH PER ARM ==="
for f in "$R"/logs/slurm_fswap_arm*.out; do
  [ -f "$f" ] || continue
  e=$(grep -oE "Epoch [0-9]+ average loss" "$f" 2>/dev/null | tail -1) || true
  echo "  $(basename $f): ${e:-no epoch line yet} | $(stat -c%s "$f") bytes"
done
echo "=== F. ERRORS ==="
grep -lE "Traceback|CUDA error|FAILED|out of memory|WRONG CODE|VERIFY FAILED" "$R"/logs/slurm_fswap_*.out "$R"/logs/slurm_fswap_*.err 2>/dev/null || echo "  none"
echo "=== DONE ==="
