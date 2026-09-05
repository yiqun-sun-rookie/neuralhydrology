set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
for J in 219423_0 219423_1 220487; do
  echo "=== JOB $J ==="
  sacct -j "${J%%_*}" -X -n -P --format=JobID,JobName,State,ExitCode,WorkDir 2>/dev/null | grep "^$J|" || true
  for F in $(ls -1 $ROOT/logs/*${J}* $ROOT/logs/**/*${J}* 2>/dev/null | head -6); do
    echo "--- $F"; tail -30 "$F" 2>/dev/null || true
  done
done
echo "=== SLURM OUT/ERR SEARCH ==="
find $ROOT -maxdepth 4 -name '*219423*' -o -maxdepth 4 -name '*220487*' 2>/dev/null | head -20 || true
exit 0
