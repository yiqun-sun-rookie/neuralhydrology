set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
cd "$ROOT"
for J in 219423_0 219423_1 220487; do
  echo "=== JOB $J ==="
  sacct -j "$J" -X -n -P --format=JobID,JobName,State,ExitCode,End 2>/dev/null || true
done
echo "=== LOG FILES matching warmpair/replv2 ==="
find "$ROOT/logs" -maxdepth 3 -newermt '2026-09-02' \( -name '*219423*' -o -name '*220487*' \) 2>/dev/null | head -20 || true
echo "=== TAILS ==="
for F in $(find "$ROOT/logs" -maxdepth 3 -newermt '2026-09-02' \( -name '*219423*' -o -name '*220487*' \) 2>/dev/null | head -8); do
  echo "--- $F ---"
  tail -40 "$F" 2>/dev/null || true
done
exit 0
