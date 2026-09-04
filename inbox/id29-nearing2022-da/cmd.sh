set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
for J in 219423_0 219423_1 220487; do
  echo "===== JOB $J ====="
  scontrol show job "$J" 2>/dev/null | tr ' ' '\n' | sed -n 's/^Std\(Out\|Err\)=//p' | head -2 || true
done
echo "=== SEARCH LOG FILES ==="
find "$ROOT/logs" -maxdepth 3 -newermt '2026-09-03' \( -name '*219423*' -o -name '*220487*' \) 2>/dev/null | head -20 || true
find "$ROOT" -maxdepth 4 -newermt '2026-09-03' \( -name '*219423*' -o -name '*220487*' \) 2>/dev/null | head -20 || true
