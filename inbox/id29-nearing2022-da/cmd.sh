set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
echo "=== sacct detail 219423 / 220487 ==="
sacct -j 219423 -X -n -P --format=JobID,JobName,State,ExitCode,Start,End,NodeList 2>/dev/null || true
sacct -j 220487 -X -n -P --format=JobID,JobName,State,ExitCode,Start,End,NodeList 2>/dev/null || true
echo "=== recent N22 jobs (last 10 days, all states) ==="
sacct -X -n -P -S $(date -d '10 days ago' +%Y-%m-%d) --format=JobID,JobName,State,ExitCode,Elapsed,End 2>/dev/null | grep -E 'N22' || echo '  none'
echo "=== logs dir listing (warmpair/replv2 only) ==="
ls -1t "$ROOT"/logs 2>/dev/null | grep -E '219423|220487' | head -20 || echo '  no logs matched in $ROOT/logs'
find "$ROOT" -maxdepth 3 -name '*219423*' -o -maxdepth 3 -name '*220487*' 2>/dev/null | head -20 || true
