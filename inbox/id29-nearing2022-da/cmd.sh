set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
for J in 219423_0 219423_1 220487; do
  echo "=== $J ==="
  scontrol show job "${J%%_*}" >/dev/null 2>&1
  for F in $(ls -1 $ROOT/logs/*219423* $ROOT/logs/*220487* 2>/dev/null | head -20); do :; done
done
echo "=== LOG FILES ==="
find $ROOT -maxdepth 4 -name '*219423*' -o -maxdepth 4 -name '*220487*' 2>/dev/null | head -30 || true
echo "=== TAIL EACH ==="
for F in $(find $ROOT -maxdepth 4 \( -name '*219423*' -o -name '*220487*' \) 2>/dev/null | head -10); do
  echo "--- $F"
  tail -30 "$F" 2>/dev/null || true
done
exit 0
