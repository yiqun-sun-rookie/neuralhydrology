set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
cd "$ROOT"
echo "=== LOG FILES ==="
ls -t logs/29_nearing2022_da_ar/ 2>/dev/null | grep -iE '219423|warmpair' || true
find "$ROOT" -maxdepth 4 -name '*219423*' -newermt '2026-09-02' 2>/dev/null | head -20 || true
echo "=== ERR TAILS ==="
for F in $(find "$ROOT" -maxdepth 5 -name '*219423*err*' -o -maxdepth 5 -name '*219423*.err' 2>/dev/null | head -4); do
  echo "--- $F"; tail -40 "$F" || true
done
echo "=== OUT TAILS ==="
for F in $(find "$ROOT" -maxdepth 5 -name '*219423*out*' 2>/dev/null | head -4); do
  echo "--- $F"; tail -30 "$F" || true
done
exit 0
