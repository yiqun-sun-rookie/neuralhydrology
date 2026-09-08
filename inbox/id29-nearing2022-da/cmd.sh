set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
date --iso-8601=seconds
for J in 219423_0 219423_1 220487; do
  echo "=== JOB $J ==="
  for F in $(ls -1 $ROOT/logs/*${J%%_*}* 2>/dev/null | head -20); do echo "-- $F"; done
done
echo "=== SEARCH LOG FILES ==="
find /data1/home/sunyiq -maxdepth 4 -name '*219423*' -o -maxdepth 4 -name '*220487*' 2>/dev/null | head -30 || true
