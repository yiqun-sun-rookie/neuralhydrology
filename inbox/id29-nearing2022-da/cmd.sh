set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
cd "$ROOT"
for J in 219423_0 219423_1 220487; do
  echo "=== JOB $J ==="
  sacct -j "$J" -X -n -P --format=JobID,JobName,State,ExitCode,WorkDir 2>/dev/null || true
done
echo "=== LOG FILES (recent, N22 warmpair/repl) ==="
ls -1t logs/29_nearing2022_da_ar/*.err logs/29_nearing2022_da_ar/*.out 2>/dev/null | head -20 || true
find "$ROOT" -maxdepth 3 -name '*21942*' -o -maxdepth 3 -name '*22048*' 2>/dev/null | head -20 || true
echo "=== TAIL OF EACH MATCH ==="
for F in $(find "$ROOT" -maxdepth 4 \( -name '*21942*' -o -name '*22048*' \) -type f 2>/dev/null | head -8); do
  echo "--- $F"
  tail -40 "$F" 2>/dev/null || true
done
exit 0
