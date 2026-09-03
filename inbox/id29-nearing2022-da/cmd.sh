set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
for J in 219423_0 219423_1; do
  echo "=== $J ==="
  scontrol show job "$J" 2>/dev/null | tr ' ' '\n' | sed -n 's/^Std\(Out\|Err\)=//p' | head -2 || true
done
echo "=== SEARCH LOG FILES ==="
find "$ROOT/logs" -newermt '2026-09-03 17:00' -name '*219423*' 2>/dev/null | head -20 || true
find /data1/home/sunyiq -maxdepth 4 -newermt '2026-09-03 17:00' -name '*219423*' 2>/dev/null | head -20 || true
echo "=== TAILS ==="
for F in $(find /data1/home/sunyiq -maxdepth 5 -name '*219423*' 2>/dev/null | head -6); do
  echo "--- $F"; tail -40 "$F" || true
done
exit 0
