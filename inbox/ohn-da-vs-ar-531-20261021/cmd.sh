#!/bin/bash
# read-only status for jobs 246200,246201
date --iso-8601=seconds
echo "=== SACCT ==="
sacct -X -n -P -j 246200,246201 --format=JobID,JobName,State,ExitCode,Elapsed,NodeList 2>&1
echo "=== SQUEUE ==="
squeue -j 246200,246201 -h -o '%i|%T|%R|%S' 2>&1
echo "=== RESERVATIONS ==="
scontrol show reservation 2>&1 | grep -E "ReservationName|StartTime|Nodes=|Flags" | head -12
echo "=== LOG MARKERS ==="
for f in "/data1/home/sunyiq/ohn_da_vs_ar_531_20261021"/logs/ohn_da_smoke-246200.out "/data1/home/sunyiq/ohn_da_vs_ar_531_20261021"/logs/ohn_da_smoke-246200.err "/data1/home/sunyiq/ohn_da_vs_ar_531_20261021"/logs/ohn_a1_smoke-246201.out "/data1/home/sunyiq/ohn_da_vs_ar_531_20261021"/logs/ohn_a1_smoke-246201.err; do [ -f "$f" ] && { echo "--- $(basename $f)"; grep -hE 'EVAL_DONE|elapsed_s|samples|SMOKE_DA_DONE|SMOKE_A1_DONE|A1_TRAIN_50_UPDATES_S|lag_relation_ok|torch|Traceback|Error|FATAL|CONDA_FAILED|MISSING|SUBMIT_FAILED' "$f" | tail -6; }; done
echo END_STATUS
