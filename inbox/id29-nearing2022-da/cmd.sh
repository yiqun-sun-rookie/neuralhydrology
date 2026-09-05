set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
for J in 219423_0 219423_1 220487; do
  echo "=== $J ==="
  SO=$(sacct -j "$J" -X -n -P --format=JobID 2>/dev/null | head -1)
  for F in $(ls -1 $ROOT/logs/*${J%%_*}* 2>/dev/null | head -8); do echo "--- $F"; tail -30 "$F" 2>/dev/null || true; done
done
echo "=== find any slurm logs ==="
find $ROOT -maxdepth 4 -name '*219423*' -o -maxdepth 4 -name '*220487*' 2>/dev/null | head -20 || true
exit 0
