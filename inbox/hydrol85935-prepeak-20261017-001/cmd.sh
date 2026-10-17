#!/bin/bash
# seq3: report smoke job 244261; ONLY if it COMPLETED with an ok record, submit the full array (6 shards).
set -o pipefail
ROOT=/data1/home/sunyiq/hydrol85935_prepeak_small_bounds_20261017_001
SJ=244261
echo "=== SMOKE ACCT ==="
sacct -X -j $SJ --format=JobID,State,ExitCode,NodeList,Elapsed -n 2>&1
ST=$(sacct -X -j $SJ --format=State -n -P 2>/dev/null | head -1 | tr -d ' ')
echo "=== SMOKE LOG ==="
for f in "$ROOT"/logs/prepeak-${SJ}_*.out "$ROOT"/logs/prepeak-${SJ}_*.err; do [ -f "$f" ] && { echo "--- $f"; tail -20 "$f"; }; done
echo "=== SMOKE RECORD ==="
R="$ROOT/smoke/records/01022500.json"
if [ -f "$R" ]; then cat "$R"; else echo "NO_RECORD_YET"; fi
if [ "$ST" != "COMPLETED" ] || ! grep -q '"status": "ok"' "$R" 2>/dev/null; then
  echo "SMOKE_NOT_READY state=$ST -> nothing submitted"; exit 0
fi
if [ -e "$ROOT/control/array_jobid.txt" ]; then echo "ARRAY_ALREADY_SUBMITTED $(cat $ROOT/control/array_jobid.txt)"; exit 0; fi
echo "=== SUBMIT ARRAY ==="
cd "$ROOT/bundle" || exit 1
out=$(sbatch --array=0-5%6 --export=ALL,STRIDE=6,LIMIT=0,OUTNAME=out prepeak.sbatch 2>&1); echo "$out"
JID=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+')
[ -n "$JID" ] || { echo SUBMIT_FAILED; exit 1; }
echo "$JID" > "$ROOT/control/array_jobid.txt"
echo "array_jobid=$JID"
sleep 5
squeue -j "$JID" -h -o '%i %P %T %R' 2>&1
