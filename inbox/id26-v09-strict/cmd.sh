#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/v09_strict
FORMAL=$ROOT/codetest/neuralhydrology/results/26_historical_band_experts/formal_v09
JID=$(cat $ROOT/predict_v09/predict_attempt_01_jobid.txt 2>/dev/null || echo "")

echo "=== A JOB ==="
sacct -j "$JID" -X -P --format=JobID,State,Partition,NodeList,Elapsed 2>&1 | head -3

echo "=== B STARTUP LOG ==="
f=$ROOT/logs/predict_${JID}.out
if [ -f "$f" ]; then echo "out_bytes=$(wc -c < $f)"; head -8 "$f"; else echo "out absent"; fi
e=$ROOT/logs/predict_${JID}.err
if [ -f "$e" ]; then echo "err_bytes=$(wc -c < $e)"; tail -8 "$e"; else echo "err absent"; fi

echo "=== C PROGRESS ==="
if [ -e "$FORMAL/predictions.building" ]; then echo "building=present"; else echo "building=absent"; fi
echo "seed_csv=$(ls $FORMAL/predictions.building/seeds/*.csv 2>/dev/null | wc -l)"
echo "idle_seconds=$(( $(date +%s) - $(stat -c %Y "$f" 2>/dev/null || date +%s) ))"
echo "=== END ==="
