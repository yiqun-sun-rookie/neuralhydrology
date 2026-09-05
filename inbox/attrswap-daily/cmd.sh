#!/bin/bash
# attrswap-daily seq=N -- READ-ONLY status of the 7 attrswap jobs (queue, accounting, log tails, medians so far).
set -o pipefail
ROOT=/data1/home/sunyiq/attr_swap_daily_2026_09
date "+wallclock %F %T %z"
echo "=== A. QUEUE (attrswap only) ==="
squeue -u "$USER" -h -o '%.11i %.28j %.9T %.10M %.9N %.8P %.30E' 2>&1 | grep attrswap || echo "  (none queued/running)"
echo "=== B. ACCOUNTING (job ids from logs/job_ids.txt) ==="
if [ -f "$ROOT/logs/job_ids.txt" ]; then
  IDS=$(awk '{print $2}' "$ROOT/logs/job_ids.txt" | paste -sd, -)
  sacct -j "$IDS" -X --format=JobID%9,JobName%28,State%12,ExitCode%8,Elapsed%10,NodeList%8,Start%19 2>&1
else echo "  job_ids.txt missing"; fi
echo "=== C. RESULTS SO FAR ==="
for f in "$ROOT"/logs/*.public_median.txt; do [ -f "$f" ] && echo "  $(basename "$f" .public_median.txt): $(cat "$f")"; done
[ -f "$ROOT/logs/attrswap_ref27_parity_s900.gate.txt" ] && echo "  GATE: $(cat "$ROOT/logs/attrswap_ref27_parity_s900.gate.txt")"
echo "=== D. LOG TAILS (last epoch line + any error) ==="
for f in "$ROOT"/logs/slurm_attrswap_*.out; do
  [ -f "$f" ] || continue
  echo "--- $(basename "$f") bytes=$(stat -c%s "$f") mtime=$(stat -c%y "$f" | cut -c1-19) ---"
  grep -E "neuralhydrology imported|WRONG|GATE|torch " "$f" 2>/dev/null | head -3 || true
  grep -E "Epoch [0-9]+ average loss" "$f" 2>/dev/null | tail -1 || true
  grep -E "RESULT|PARITY GATE|DONE|Traceback|Error|error|Killed|out of memory|STOP" "$f" 2>/dev/null | tail -3 || true
done
for f in "$ROOT"/logs/slurm_attrswap_*.err; do [ -s "$f" ] && { echo "--- $(basename "$f") (stderr, last 3 non-progress lines) ---"; grep -v '%|' "$f" | tail -3; }; done
echo "=== DONE ==="
