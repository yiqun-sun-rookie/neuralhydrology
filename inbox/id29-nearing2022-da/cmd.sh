set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
for J in 219423_0 219423_1 220487; do
  echo "=== $J ==="
  SO=$(sacct -j "$J" -X -n -P --format=JobID 2>/dev/null | head -1)
  for F in $(ls -1 $ROOT/logs/*219423*.err $ROOT/logs/*220487*.err ~/nearing2022_da/logs/*219423* 2>/dev/null | head -20); do echo "  file:$F"; done
done
echo "=== SEARCH LOG DIRS ==="
find $ROOT -maxdepth 3 -name '*219423*' 2>/dev/null | head -20
find $ROOT -maxdepth 3 -name '*220487*' 2>/dev/null | head -20
echo "=== TAIL EACH ==="
for F in $(find $ROOT -maxdepth 3 \( -name '*219423*' -o -name '*220487*' \) -type f 2>/dev/null | head -10); do
  echo "----- $F"; tail -40 "$F" || true
done
exit 0
