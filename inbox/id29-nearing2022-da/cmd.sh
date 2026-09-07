set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
for J in 219423_0 219423_1 220487; do
  echo "=== $J ==="
  SO=$(sacct -j "$J" -X -n -P --format=JobID 2>/dev/null | head -1)
  for F in $(ls -1 $ROOT/logs/*/*${J%%_*}* $ROOT/logs/*${J%%_*}* 2>/dev/null | head -8); do echo "-- $F"; done
done
echo "=== SEARCH LOG FILES ==="
find $ROOT/logs -maxdepth 3 -newermt '2026-09-02' \( -name '*21942*' -o -name '*22048*' \) 2>/dev/null | head -20 || true
