set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
for J in 219423_0 219423_1 220487; do
  echo "=== $J ==="
  SO=$(sacct -j "$J" -n -P --format=JobID,WorkDir 2>/dev/null | head -1)
  echo "workdir: $SO"
done
echo "=== LOG FILES ==="
ls -t $ROOT/logs/*warm* $ROOT/logs/*repl* 2>/dev/null | head -20 || true
find $ROOT -maxdepth 3 -name '*219423*' -o -maxdepth 3 -name '*220487*' 2>/dev/null | head -20 || true
