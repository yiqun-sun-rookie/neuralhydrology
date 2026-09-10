set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
for J in 219423_0 219423_1 220487; do
  echo "=== $J ==="
  SO=$(sacct -j "$J" -X -n -P --format=WorkDir 2>/dev/null | head -1)
  echo "workdir=$SO"
done
echo "=== LOG FILES (warmpair / replv2) ==="
find "$ROOT/logs" -maxdepth 3 -newermt '2026-09-02' \( -name '*219423*' -o -name '*220487*' \) 2>/dev/null | head -20 || true
echo "=== ERR TAILS ==="
for F in $(find "$ROOT" -maxdepth 4 -name '*219423*.err' -o -maxdepth 4 -name '*220487*.err' 2>/dev/null | head -10); do
  echo "--- $F"; tail -40 "$F" 2>/dev/null || true
done
exit 0
