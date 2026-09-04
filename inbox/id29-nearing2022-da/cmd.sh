set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
for J in 219423_0 219423_1 220487; do
  echo "=== $J ==="
  scontrol show job "${J%%_*}" >/dev/null 2>&1
  for P in $(ls -1 $ROOT/logs/*${J}* $ROOT/logs/**/*${J}* /data1/home/sunyiq/nearing2022_da/logs/29_nearing2022_da_ar/*${J}* 2>/dev/null | head -6); do
    echo "--- $P"; tail -40 "$P" 2>/dev/null || true
  done
done
echo "=== SEARCH LOGS BY JOBID ==="
find $ROOT/logs -maxdepth 3 -newermt '2026-09-03' \( -name '*219423*' -o -name '*220487*' \) 2>/dev/null | head -20 || true
exit 0
