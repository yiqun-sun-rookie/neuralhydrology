set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
for J in 219423_0 219423_1 220487; do
  echo "=== $J ==="
  scontrol show job "$J" 2>/dev/null | tr ' ' '\n' | sed -n 's/^Std\(Out\|Err\)=//p' | sort -u || true
done
echo "=== LOG FILES (logs dir, N22 recent) ==="
find "$ROOT/logs" -maxdepth 3 -newermt '2026-09-03' \( -name '*219423*' -o -name '*220487*' \) 2>/dev/null | head -40 || true
find /data1/home/sunyiq -maxdepth 4 -newermt '2026-09-03' \( -name '*219423*' -o -name '*220487*' \) 2>/dev/null | head -40 || true
exit 0
