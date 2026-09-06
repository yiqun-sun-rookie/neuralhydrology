set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
cd "$ROOT"
for J in 219423_0 219423_1 220487; do
  echo "=== $J paths ==="
  sacct -j "$J" -X -n -P --format=JobID,JobName,State,End,WorkDir 2>/dev/null || true
done
echo "=== locate log files ==="
find "$ROOT/logs" -maxdepth 3 -newermt '2026-09-03' \( -name '*219423*' -o -name '*220487*' \) 2>/dev/null | head -20 || true
find "$ROOT" -maxdepth 3 -newermt '2026-09-03' \( -name '*219423*' -o -name '*220487*' \) 2>/dev/null | head -20 || true
echo "=== tails ==="
for F in $(find "$ROOT" -maxdepth 4 \( -name '*219423*' -o -name '*220487*' \) 2>/dev/null | head -10); do
  echo "--- $F ---"
  tail -40 "$F" 2>/dev/null || true
done
exit 0
