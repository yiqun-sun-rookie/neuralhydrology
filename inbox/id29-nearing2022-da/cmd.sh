set -o pipefail
for J in 219423_0 219423_1 220487; do
  echo "=== $J ==="
  SO=$(sacct -j "$J" -X -n -P --format=JobID,WorkDir 2>/dev/null | head -1)
  echo "  $SO"
done
echo "=== LOG FILES ==="
ls -1t /data1/home/sunyiq/nearing2022_da/logs/29_nearing2022_da_ar/ 2>/dev/null | head -30 || echo none
