set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
cd "$ROOT"
for J in 219423_0 219423_1 220487; do
  echo "=== $J ==="
  SO=$(sacct -j "$J" -X -n -P --format=JobID 2>/dev/null | head -1)
  for F in $(ls -1 logs/*/*${J%%_*}* 2>/dev/null | head -20; ls -1 logs/*${J%%_*}* 2>/dev/null | head -20); do echo "  file: $F"; done
done
echo "=== SEARCH LOG DIRS ==="
find "$ROOT" -maxdepth 3 -name '*219423*' -o -maxdepth 3 -name '*220487*' 2>/dev/null | head -30
