#!/bin/bash
# id26-v09-strict seq=25 : immediate post-submit verification, no waiting loop.
export LC_ALL=C
ROOT=/data1/home/sunyiq/v09_strict
CODE=$ROOT/codetest/neuralhydrology
JID=$(cat "$ROOT/suite_jobid.txt" 2>/dev/null || echo 202054)
echo "=== JOB ==="
squeue -j "$JID" -o '%.10i %.12T %.12M %.20S %.20R' 2>&1
sacct -j "$JID" -X --format=JobID%10,State%12,ExitCode%8,Start%20,Elapsed%12 2>&1 | head -4
echo "=== CODE ==="
"$ROOT/gitenv/bin/git" -C "$CODE" rev-parse --abbrev-ref HEAD 2>&1
"$ROOT/gitenv/bin/git" -C "$CODE" rev-parse HEAD 2>&1
echo "=== PROGRESS ==="
find "$CODE/results/26_historical_band_experts/formal_v09" -maxdepth 2 -name 'seed_*' 2>/dev/null | sed 's|.*formal_v09/||' | sort
echo "=== LOG TAIL ==="
tail -30 "$ROOT/logs/suite_remaining_${JID}.out" 2>&1
tail -20 "$ROOT/logs/suite_remaining_${JID}.err" 2>&1
echo "=== END ==="
