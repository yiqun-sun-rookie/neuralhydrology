set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
for J in 219423_0 219423_1 220487; do
  echo "=== JOB $J ==="
  SO=$(sacct -j "$J" -X -n -P --format=JobID 2>/dev/null | head -1)
  for F in $(ls -1t $ROOT/logs/*${J%%_*}*.err $ROOT/logs/*${J%%_*}*.out 2>/dev/null | head -6); do
    echo "--- $F ---"; tail -30 "$F" 2>/dev/null || true
  done
done
echo "=== LOG DIR CANDIDATES ==="
ls -1dt $ROOT/logs 2>/dev/null || true
find $ROOT -maxdepth 3 -name '*219423*' 2>/dev/null | head -20 || true
find $ROOT -maxdepth 3 -name '*220487*' 2>/dev/null | head -20 || true
exit 0
