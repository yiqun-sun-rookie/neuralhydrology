set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
echo "=== 219423 sacct detail ==="
sacct -j 219423 -n -P --format=JobID,JobName,State,ExitCode,Start,End,NodeList 2>/dev/null || true
echo "=== 220487 replv2 detail ==="
sacct -j 220487 -n -P --format=JobID,JobName,State,ExitCode,Start,End,NodeList 2>/dev/null || true
for J in 219423_0 219423_1 220487; do
  echo "=== LOGS for $J ==="
  for SO in $(scontrol show job "${J}" 2>/dev/null | tr ' ' '\n' | sed -n -e 's/^StdOut=//p' -e 's/^StdErr=//p' | sort -u); do
    echo "--- $SO"; tail -40 "$SO" 2>/dev/null || echo "  unreadable"
  done
done
echo "=== recent log files in logs dir ==="
ls -lt "$ROOT/logs" 2>/dev/null | head -20 || true
echo "=== slurm out/err by pattern ==="
find "$ROOT" -maxdepth 3 -name '*219423*' -o -maxdepth 3 -name '*220487*' 2>/dev/null | head -20 || true
exit 0
