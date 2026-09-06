set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
cd "$ROOT"
echo "=== find warmpair logs ==="
find "$ROOT/logs" -maxdepth 3 -name '*219423*' -newermt '2026-09-01' 2>/dev/null | head -20 || true
find "$ROOT" -maxdepth 4 -name '*219423*' 2>/dev/null | head -20 || true
for J in 219423_0 219423_1 220487; do
  echo "=== scontrol/sacct paths $J ==="
  sacct -j "$J" -n -P --format=JobID,JobName,WorkDir 2>/dev/null | head -3 || true
done
echo "=== tail err files ==="
for F in $(find "$ROOT" -name '*219423*.err' -o -name '*219423*.out' -o -name '*220487*.err' -o -name '*220487*.out' 2>/dev/null | head -8); do
  echo "--- $F"; tail -40 "$F" 2>/dev/null || true
done
exit 0
