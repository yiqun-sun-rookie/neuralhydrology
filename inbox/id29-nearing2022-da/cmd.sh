set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
cd "$ROOT"
echo "=== LOG FILES ==="
find logs -maxdepth 3 -name '*219423*' -o -maxdepth 3 -name '*220487*' 2>/dev/null | head -20 || true
for J in 219423_0 219423_1 220487; do
  echo "=== SACCT PATH $J ==="
  sacct -j "$J" -X -n -P --format=JobID,WorkDir 2>/dev/null | head -2 || true
done
echo "=== SEARCH ERR ==="
find "$ROOT" -maxdepth 4 -name '*21942*' -newermt '2026-09-02' 2>/dev/null | head -20 || true
find "$ROOT" -maxdepth 4 -name '*22048*' -newermt '2026-09-02' 2>/dev/null | head -20 || true
for F in $(find "$ROOT" -maxdepth 4 \( -name '*21942*.err' -o -name '*21942*.out' -o -name '*22048*.err' \) 2>/dev/null | head -6); do
  echo "----- $F -----"; tail -40 "$F" || true
done
exit 0
