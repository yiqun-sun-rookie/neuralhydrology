set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
cd "$ROOT"
for J in 219423_0 219423_1 220487; do
  echo "=== $J ==="
  sacct -j "${J%%_*}" -n -P --format=JobID,JobName,WorkDir%200 2>/dev/null | head -3 || true
done
echo "=== LOG FILES (warmpair / replv2) ==="
find "$ROOT/logs" -maxdepth 3 -newermt '2026-09-03' \( -name '*219423*' -o -name '*220487*' \) 2>/dev/null | head -20 || true
find "$ROOT" -maxdepth 4 -newermt '2026-09-03' \( -name '*219423*' -o -name '*220487*' \) 2>/dev/null | head -20 || true
echo "=== TAILS ==="
for F in $(find "$ROOT" -maxdepth 5 \( -name '*219423*' -o -name '*220487*' \) 2>/dev/null | head -12); do
  echo "--- $F"; tail -40 "$F" 2>/dev/null || true
done
exit 0
