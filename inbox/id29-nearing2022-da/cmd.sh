set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
for J in 219423_0 219423_1 220487; do
  echo "=== $J ==="
  SE=$(sacct -j "$J" -X -n -P --format=JobID 2>/dev/null | head -1)
  for F in $(scontrol show job "$J" 2>/dev/null | tr ' ' '\n' | sed -n 's/^Std\(Err\|Out\)=//p' | head -2); do echo "-- $F"; tail -40 "$F" 2>/dev/null || true; done
done
echo "=== SEARCH LOG FILES ==="
ls -1t "$ROOT"/logs/29_nearing2022_da_ar/ 2>/dev/null | head -30 || true
