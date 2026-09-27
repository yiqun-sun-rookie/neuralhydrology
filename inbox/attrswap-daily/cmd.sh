#!/bin/bash
# READ-ONLY status probe for the GPM-era contract (gate 228080, array 228081). No sbatch, no scancel, no writes.
# Median NSE is never printed. No backslash literals.
set -o pipefail
date "+wallclock %F %T %z"
R=/data1/home/sunyiq/precip_swap4_gpm_daily_2026_09
cd "$R" || { echo "ROOT MISSING"; exit 1; }
echo "=== A. sacct ==="
sacct -j 228080,228081 -X -S 2026-09-27 --format=JobID%16,JobName%14,State%12,Elapsed,ExitCode,NodeList%10 2>&1 | head -40
echo "  state tally (array tasks):"
sacct -j 228081 -X -n -P -S 2026-09-27 --format=State 2>/dev/null | sort | uniq -c | sed 's/^/    /'
echo "=== B. queue ==="
squeue -u "$USER" -o '%.16i %.14j %.9T %.10M %.9P %R' 2>&1 | grep -Ei 'pswap4|JOBID'
echo "=== C. gate ==="
[ -f logs/gate_ok.txt ] && echo "  $(cat logs/gate_ok.txt)" || echo "  gate_ok.txt: not yet"
g=$(ls logs/slurm_pswap4_gate_228080.out 2>/dev/null)
[ -n "$g" ] && grep -E "FAIL|checks passed|combined hash|smoke .* OK|GATE|Error|error" "$g" | head -30 | sed 's/^/  /'
e=$(ls logs/slurm_pswap4_gate_228080.err 2>/dev/null)
[ -n "$e" ] && [ -s "$e" ] && { echo "  --- gate stderr tail ---"; tail -5 "$e" | sed 's/^/  /'; }
echo "=== D. arms ==="
echo "  run dirs: $(ls -d runs/pswap4_* 2>/dev/null | wc -l)  test_metrics: $(find runs -name test_metrics.csv 2>/dev/null | wc -l)"
for f in $(ls logs/slurm_pswap4_arm_228081_*.out 2>/dev/null); do
  t=$(basename $f .out)
  st=$(grep -c "ARM DONE" $f)
  ep=$(grep -oE "Epoch [0-9]+ average loss" $f | tail -1)
  echo "  $t done=$st last='$ep' $(grep -m1 -oE 'cfg [a-z0-9_]+' $f)"
done
echo "  arm stderr with Traceback: $(grep -l Traceback logs/slurm_pswap4_arm_228081_*.err 2>/dev/null | wc -l)"
echo "=== DONE (read-only) ==="
