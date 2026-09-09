set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
date --iso-8601=seconds
for J in 219423_0 219423_1 220487; do
  echo "=== $J ==="
  sacct -j "$J" -n -P --format=JobID,JobName,State,ExitCode,WorkDir%200 2>/dev/null | head -3 || true
  for F in $(ls -1 $ROOT/logs/*${J%%_*}* 2>/dev/null | head -6; ls -1 ~/*${J%%_*}* 2>/dev/null | head -6); do
    echo "--- $F"; tail -30 "$F" 2>/dev/null || true
  done
done
echo "=== SEARCH LOG DIRS ==="
find $ROOT -maxdepth 3 -name '*219423*' -o -maxdepth 3 -name '*220487*' 2>/dev/null | head -20 || true
exit 0
