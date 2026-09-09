set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
for J in 219423_0 219423_1 220487; do
  echo "=== JOB $J ==="
  sacct -j "$J" -n -P --format=JobID,JobName,State,ExitCode,WorkDir 2>/dev/null | head -3 || true
done
echo "=== LOG FILES (logs dir, N22 warm/repl only) ==="
find "$ROOT" -maxdepth 4 -name '*219423*' -o -maxdepth 4 -name '*220487*' 2>/dev/null | head -40 || true
ls -1t ~/nearing2022_da/logs 2>/dev/null | grep -E '219423|220487' | head -20 || echo '  no logs dir match'
