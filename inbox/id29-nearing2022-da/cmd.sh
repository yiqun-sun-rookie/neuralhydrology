set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
for J in 219423_0 219423_1 220487; do
  echo "===== $J ====="
  scontrol show job "${J%%_*}" >/dev/null 2>&1
  for F in $(ls -1 $ROOT/logs/*${J%%_*}* $ROOT/logs/**/*${J%%_*}* 2>/dev/null | head -6); do echo "-- $F"; done
done
echo "=== find recent err/out ==="
find $ROOT -maxdepth 4 -name '*21942*' -o -maxdepth 4 -name '*22048*' 2>/dev/null | head -20
