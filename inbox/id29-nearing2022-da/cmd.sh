set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
echo "=== find logs for 219423 / 220487 ==="
for J in 219423_0 219423_1 220487; do
  echo "--- $J ---"
  F=$(find "$ROOT" -maxdepth 4 -name "*${J}*" -newermt '2026-09-01' 2>/dev/null | head -20)
  echo "$F" | head -20
done
echo "=== logs dir listing (recent) ==="
ls -lt "$ROOT/logs" 2>/dev/null | head -20 || true
ls -lt /data1/home/sunyiq/nearing2022_da/slurm_logs 2>/dev/null | head -20 || true
echo "=== tails ==="
for P in $(find "$ROOT" -name '*21942*' -o -name '*220487*' 2>/dev/null | grep -E '\.(err|out)$' | head -6); do
  echo "--- $P ---"; tail -30 "$P" 2>/dev/null || true
done
exit 0
