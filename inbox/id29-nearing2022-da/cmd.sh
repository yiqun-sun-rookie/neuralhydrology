set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
for J in 219423_0 219423_1 220487; do
  echo "===== $J ====="
  scontrol show job "$J" >/dev/null 2>&1
  F=$(ls -1 $ROOT/logs/*${J%%_*}* 2>/dev/null | head -20)
  echo "$F"
done
echo "=== search log files ==="
find $ROOT -maxdepth 4 -name '*219423*' -o -maxdepth 4 -name '*220487*' 2>/dev/null | head -20
