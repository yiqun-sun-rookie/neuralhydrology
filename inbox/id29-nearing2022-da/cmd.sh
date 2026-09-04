set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
for J in 219423_0 219423_1 220487; do
  echo "=== $J ==="
  for K in StdErr StdOut; do :; done
  P=$(sacct -j "$J" -X -n -P --format=JobID,WorkDir 2>/dev/null | head -1)
  echo "  $P"
done
echo "=== LOG FILES (recent) ==="
ls -1t $ROOT/logs/*.err 2>/dev/null | head -20 || true
ls -1t $ROOT/logs/29_nearing2022_da_ar/*.err 2>/dev/null | head -20 || true
find $ROOT -maxdepth 3 -name '*219423*' -o -maxdepth 3 -name '*220487*' 2>/dev/null | head -30 || true
