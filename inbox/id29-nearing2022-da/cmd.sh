set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
for J in 219423_0 219423_1 220487; do
  echo "=== $J ==="
  SO=$(sacct -j "$J" -X -n -P --format=JobName 2>/dev/null | head -1)
  echo "  name=$SO"
done
echo "=== find logs ==="
find "$ROOT/logs" -maxdepth 3 -newermt '2026-09-01' \( -name '*219423*' -o -name '*220487*' \) 2>/dev/null | head -20 || true
