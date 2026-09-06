set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
for J in 219423_0 219423_1 220487; do
  echo "=== $J paths ==="
  sacct -j "$J" -X -n -P --format=JobID,JobName,State,WorkDir 2>/dev/null || true
done
echo "=== candidate log files ==="
ls -1t "$ROOT"/logs/29_nearing2022_da_ar/*219423* "$ROOT"/logs/29_nearing2022_da_ar/*220487* 2>/dev/null | head -20 || true
ls -1t "$ROOT"/logs/*219423* "$ROOT"/logs/*220487* 2>/dev/null | head -20 || true
find "$ROOT" -maxdepth 4 -name '*219423*' -newermt '2026-09-01' 2>/dev/null | head -20 || true
echo "=== tails ==="
for F in $(find "$ROOT" -maxdepth 4 \( -name '*219423*' -o -name '*220487*' \) 2>/dev/null | head -10); do
  echo "--- $F ---"
  tail -40 "$F" 2>/dev/null || true
done
exit 0
