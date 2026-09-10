set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
for J in 219423_0 219423_1 220487; do
  echo "=== $J ==="
  SO=$(sacct -j "$J" -X -n -P --format=WorkDir 2>/dev/null | head -1)
  echo "workdir=$SO"
done
echo "=== FIND LOGS ==="
find "$ROOT/logs" "$ROOT" -maxdepth 3 -name '*21942*' -o -maxdepth 3 -name '*22048*' 2>/dev/null | head -20 || true
