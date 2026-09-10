set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
echo "=== find logs for 219423 / 220487 ==="
for J in 219423_0 219423_1 220487; do
  echo "--- $J ---"
  sacct -j "$J" -X -n -P --format=JobID,JobName,State,ExitCode,Start,End,WorkDir 2>/dev/null || true
done
echo "=== log files ==="
ls -1t $ROOT/logs/*219423* $ROOT/logs/*220487* 2>/dev/null || true
find $ROOT -maxdepth 3 -name '*219423*' -o -maxdepth 3 -name '*220487*' 2>/dev/null | head -20 || true
