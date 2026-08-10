#!/bin/bash
# id26-v09-strict seq=40 : two-hour status check, no waiting loop.
export LC_ALL=C
ROOT=/data1/home/sunyiq/v09_strict
CODE=$ROOT/codetest/neuralhydrology
FORMAL=$CODE/results/26_historical_band_experts/formal_v09
JID=$(cat "$ROOT/suite_jobid.txt" 2>/dev/null || echo 202054)
echo "=== JOB ==="
squeue -j "$JID" -o '%.10i %.12T %.12M %.20S %.20R' 2>&1
sacct -j "$JID" -X --format=JobID%10,State%12,ExitCode%8,Start%20,Elapsed%12 2>&1 | head -4
echo "=== PROGRESS SUMMARY ==="
echo "completed=$(find "$FORMAL" -mindepth 3 -maxdepth 3 -type f -name manifest.json -path '*/seed_[0-9]*/manifest.json' 2>/dev/null | wc -l)"
echo "building=$(find "$FORMAL" -mindepth 2 -maxdepth 2 -type d -name 'seed_*.building' 2>/dev/null | wc -l)"
echo "failed=$(find "$FORMAL" -mindepth 2 -maxdepth 2 -type d -name 'seed_*.failed' 2>/dev/null | wc -l)"
echo "=== CURRENT BUILDING ==="
find "$FORMAL" -mindepth 2 -maxdepth 2 -type d -name 'seed_*.building' 2>/dev/null | sed 's|.*formal_v09/||' | sort
echo "=== FAILED DIRS ==="
find "$FORMAL" -mindepth 2 -maxdepth 2 -type d -name 'seed_*.failed' 2>/dev/null | sed 's|.*formal_v09/||' | sort
echo "=== FAILURE RECORD ==="
if [ -f "$FORMAL/training_attempt_01.failure.json" ]; then
  sed -n '1,160p' "$FORMAL/training_attempt_01.failure.json"
else
  echo "none"
fi
echo "=== COMPLETED RUNS ==="
find "$FORMAL" -mindepth 3 -maxdepth 3 -type f -name manifest.json -path '*/seed_[0-9]*/manifest.json' 2>/dev/null | sed 's|/manifest.json$||; s|.*formal_v09/||' | sort
echo "=== LOG TAIL ==="
tail -30 "$ROOT/logs/suite_remaining_${JID}.out" 2>&1
echo "=== ERROR TAIL ==="
tail -30 "$ROOT/logs/suite_remaining_${JID}.err" 2>&1
echo "=== END ==="
