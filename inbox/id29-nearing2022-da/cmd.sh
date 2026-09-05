set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
for J in 219423_0 219423_1 220487; do
  echo "=== $J ==="
  scontrol show job "$J" >/dev/null 2>&1
  F=$(sacct -j "$J" -X -n -P --format=JobID 2>/dev/null | head -1)
  for L in $(ls -1 $ROOT/logs/*${J}* $ROOT/logs/**/*${J}* 2>/dev/null | head -5); do
    echo "--- $L"; tail -n 30 "$L" 2>/dev/null || true
  done
done
echo "=== find any slurm logs by pattern ==="
find $ROOT -maxdepth 4 -name '*219423*' -o -maxdepth 4 -name '*220487*' 2>/dev/null | head -20 || true
exit 0
