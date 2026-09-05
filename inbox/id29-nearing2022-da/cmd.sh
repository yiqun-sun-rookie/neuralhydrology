set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
cd "$ROOT"
for J in 219423_0 219423_1 220487; do
  echo "=== $J ==="
  scontrol show job "${J%%_*}" >/dev/null 2>&1
  sacct -j "$J" -X -n -P --format=JobID,JobName,State,ExitCode,Submit,End 2>/dev/null || true
done
echo "=== LOG FILES (recent N22 logs) ==="
ls -1t logs/29_nearing2022_da_ar/*.err 2>/dev/null | head -12 || true
ls -1t ~/nearing2022_da/logs/*.err 2>/dev/null | head -12 || true
echo "=== SEARCH FOR WARMPAIR/REPL LOGS ==="
find "$ROOT/logs" -maxdepth 3 -name '*21942*' -o -maxdepth 3 -name '*22048*' 2>/dev/null | head -20 || true
