set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
for J in 219423_0 219423_1 220487; do
  echo "=== $J ==="
  for F in $(sacct -j "$J" -X -n -P --format=JobID 2>/dev/null); do :; done
  P=$(scontrol show job "${J%%_*}" 2>/dev/null | tr ' ' '\n' | sed -n 's/^StdErr=//p' | head -1)
  echo "  scontrol StdErr=$P"
done
echo "=== SEARCH LOG FILES ==="
find "$ROOT/logs" -maxdepth 3 -newermt '2026-09-02' \( -name '*219423*' -o -name '*220487*' \) 2>/dev/null | head -20
find /data1/home/sunyiq -maxdepth 4 -name '*219423*' 2>/dev/null | head -20
echo "=== TAILS ==="
for F in $(find /data1/home/sunyiq -maxdepth 5 \( -name '*219423*' -o -name '*220487*' \) 2>/dev/null | head -8); do
  echo "--- $F"; tail -n 30 "$F" 2>/dev/null || true
done
exit 0
