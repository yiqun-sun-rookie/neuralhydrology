set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
cd "$ROOT"
for J in 219423_0 219423_1 220487; do
  echo "===== $J ====="
  SO=$(sacct -j "$J" -X -n -P --format=JobName 2>/dev/null | head -1)
  echo "name=$SO"
  for F in $(ls -1t logs/*${J%%_*}* 2>/dev/null | head -6); do echo "--- $F"; tail -30 "$F" 2>/dev/null || true; done
done
echo "===== find any slurm logs ====="
ls -1t $(find "$ROOT" -maxdepth 3 -name '*219423*' -o -maxdepth 3 -name '*220487*' 2>/dev/null | head -20) 2>/dev/null | head -20 || true
exit 0
