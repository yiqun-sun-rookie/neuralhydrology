#!/bin/bash
export LC_ALL=C
DST=/data1/home/$USER/adv531
R=$DST/results/05_adversarial_robustness/id18_s100_hpc
echo "=== QUEUE ==="
squeue -u $USER -o "%.14i %.16j %.3t %.11M %.20R" 2>&1 | head -30
echo "running=$(squeue -u $USER -h -r -t R 2>/dev/null | wc -l)  pending=$(squeue -u $USER -h -r -t PD 2>/dev/null | wc -l)"
echo "=== SACCT ==="
sacct -S 2026-08-06T17:20 -u $USER -X --format=JobID%14,JobName%16,State%12,ExitCode%8,Elapsed%10 2>&1 | grep -E "adv531|JobID|----" | head -50
echo "=== PER-BLOCK PROGRESS (basins written / 531) ==="
for b in exp2 exp3 exp4 exp5 exp6 detect ksweep; do
  n=0
  for f in $R/${b}_531_chunk*.json; do
    [ -f "$f" ] || continue
    c=$(grep -c '\"basin\"' "$f" 2>/dev/null || echo 0)
    n=$((n + c))
  done
  printf "  %-8s %4d / 531\n" "$b" "$n"
done
if [ -d $R/l1l2_531 ]; then
  printf "  %-8s %4d / 531\n" "l1l2" "$(ls $R/l1l2_531/l1l2_records/*.npz 2>/dev/null | wc -l)"
fi
echo "=== ERRORS ==="
grep -l "Traceback\|FATAL\|CUDA out of memory" $DST/logs/adv531_*.err $DST/logs/adv531_*.out 2>/dev/null | head -8 || echo "  none"
echo "=== NEWEST LOG LINES ==="
for f in $(ls -t $DST/logs/adv531_*.out 2>/dev/null | head -4); do echo "--- $(basename $f)"; tail -2 "$f"; done
