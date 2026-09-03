set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
for T in 0 1; do
  echo "=== TASK $T ==="
  SO=$(sacct -j 219423_$T -X -n -P --format=JobID 2>/dev/null | head -1)
  for F in $(ls -1t $ROOT/logs/*219423*${T}* $ROOT/logs/**/*219423*${T}* 2>/dev/null | head -4); do
    echo "--- $F"; tail -40 "$F" 2>/dev/null || true
  done
done
echo "=== FIND ANY 219423 LOGS ==="
find $ROOT/logs -name '*219423*' -newermt '2026-09-01' 2>/dev/null | head -20 || true
exit 0
