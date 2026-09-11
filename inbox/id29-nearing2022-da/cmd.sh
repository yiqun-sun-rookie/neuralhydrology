set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
date --iso-8601=seconds
echo "=== N22 JOBS ==="
squeue -u sunyiq -h -o '%.12i %.16j %.9T %.11M %.11L %R' 2>/dev/null | grep -E 'N22' || echo 'no N22 jobs in queue'
echo "=== WARM JOBS SINCE 09-01 ==="
sacct -X -n -P -S 2026-09-01 --format=JobID,JobName,State,ExitCode,Elapsed,End 2>/dev/null | grep -Ei 'warm' || echo '  none'
echo "=== WARMPAIR DIRS ==="
D="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics/warmup_pair"
for X in control_seed0_repeat1 masked_seed0_repeat1 paired_analysis; do [ -e "$D/$X" ] && echo "  PRESENT $X" || echo "  MISSING $X"; done
echo "=== 219423 STDERR/STDOUT PATHS ==="
for J in 219423_0 219423_1 220487; do
  for F in $(sacct -j "$J" -n -P --format=StdErr,StdOut 2>/dev/null | head -1 | tr '|' ' '); do
    echo "--- $J $F"; [ -f "$F" ] && tail -n 25 "$F" || echo "  (no file)"
  done
done
echo "=== LOG DIR GUESS ==="
ls -t "$ROOT/logs/29_nearing2022_da_ar" 2>/dev/null | grep -Ei 'warm|219423|220487' | head -10 || true
for F in $(ls -t "$ROOT/logs/29_nearing2022_da_ar" 2>/dev/null | grep -Ei '219423' | head -4); do echo "--- $F"; tail -n 25 "$ROOT/logs/29_nearing2022_da_ar/$F" || true; done
exit 0
