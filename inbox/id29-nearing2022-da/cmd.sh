set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
date --iso-8601=seconds
sacct -j 217227 -X -n -P --format=JobID,State,ExitCode,Elapsed 2>/dev/null || echo 'no sacct'
squeue -h -j 217227 -o '%.12i %.9T %R' 2>/dev/null || echo 'not in queue'
P="$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
if [ -f "$P" ]; then echo "GATE PRESENT ($(stat -c %s "$P") bytes)"; cat "$P"; else echo "GATE MISSING"; fi
exit 0
