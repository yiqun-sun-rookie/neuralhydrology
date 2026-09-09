#!/bin/bash
# precip-swap status -- READ-ONLY. Queue, accounting, build reports, medians, latest epoch, errors.
set -o pipefail
date "+wallclock %F %T %z"
R=/data1/home/sunyiq/precip_swap_daily_2026_09
echo "=== A. QUEUE ==="
squeue -u "$USER" -o '%.11i %.24j %.9T %.10M %.9N %.18E' 2>&1 | grep -Ei 'pswap|JOBID' || echo '  (none queued)'
echo "=== B. ACCOUNTING ==="
ids=$(tr '\n' ',' < "$R/logs/job_ids.txt" | sed 's/,$//')
sacct -j "$ids" -X --format=JobID%9,JobName%24,State%12,ExitCode%8,Elapsed%10,NodeList%9 2>&1
echo "=== C. GATE + BUILD REPORTS ==="
cat "$R/logs/gate.txt" 2>/dev/null || echo "  (gate marker absent)"
for f in "$R"/logs/build_*.json; do
  [ -f "$f" ] || continue
  echo "--- $(basename $f) ---"
  python -c "
import json,sys
d=json.load(open(sys.argv[1]))
print(' product=%s written=%s failures=%d lag0_share=%.4f' % (d['product'], d['written'], len(d['failures']), d['lag0_share']))
print(' ratio_over_maurer:', d['ratio_over_maurer'])
print(' v6_off_lag basins:', len(d.get('v6_off_lag_basins', [])))
for n in d.get('notes', []): print(' NOTE', n[:160])
for x in d['failures'][:3]: print(' FAIL', x[:160])
" "$f" 2>&1 || cat "$f"
done
echo "=== D. MEDIANS ==="
for f in "$R"/logs/*.public_median.txt; do [ -f "$f" ] && echo "  $(basename $f .public_median.txt): $(cat $f)"; done
echo "medians present: $(ls "$R"/logs/*.public_median.txt 2>/dev/null | wc -l)/6"
echo "=== E. LATEST EPOCH PER ARM ==="
for g in "$R"/logs/slurm_pswap_armP*.out; do
  [ -f "$g" ] || continue
  e=$(grep -oE "Epoch [0-9]+ average loss" "$g" 2>/dev/null | tail -1) || true
  echo "  $(basename $g): ${e:-starting}"
done
echo "=== F. ERRORS ==="
grep -lE "Traceback|CUDA error|out of memory|WRONG CODE|核验失败" "$R"/logs/slurm_pswap_*.out "$R"/logs/slurm_pswap_*.err 2>/dev/null || echo "  none"
echo "=== DONE ==="
