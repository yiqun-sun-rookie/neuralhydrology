set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
for J in 219423_0 219423_1 220487; do
  echo "=== $J ==="
  scontrol show job "$J" 2>/dev/null | tr ' ' '\n' | sed -n 's/^Std\(Out\|Err\)=//p' | head -2 || true
done
echo "=== SEARCH LOG FILES ==="
ls -1t $ROOT/logs/29_nearing2022_da_ar/ 2>/dev/null | head -30 || true
find $ROOT/logs -name '*219423*' -o -name '*220487*' 2>/dev/null | head -20 || true
echo "=== ERR TAILS ==="
for F in $(find $ROOT/logs -name '*219423*' -o -name '*220487*' 2>/dev/null | head -8); do
  echo "--- $F ---"; tail -n 30 "$F" 2>/dev/null || true
done
exit 0
