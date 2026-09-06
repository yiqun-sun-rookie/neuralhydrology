set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
cd "$ROOT" || exit 0
echo "=== find warmpair logs ==="
find "$ROOT/logs" -maxdepth 3 -name '*219423*' -newermt '2026-09-01' 2>/dev/null | head -20 || true
find "$ROOT" -maxdepth 4 -name '*219423*' 2>/dev/null | head -20 || true
echo "=== find replv2 220487 logs ==="
find "$ROOT" -maxdepth 4 -name '*220487*' 2>/dev/null | head -20 || true
echo "=== dump tails ==="
for F in $(find "$ROOT" -maxdepth 4 \( -name '*219423*' -o -name '*220487*' \) 2>/dev/null | head -8); do
  echo "---- $F"; tail -n 40 "$F" 2>/dev/null || true
done
echo "=== scontrol stdout paths ==="
sacct -j 219423 -n -P --format=JobID,WorkDir 2>/dev/null | head -5 || true
exit 0
