#!/bin/bash
# read-only status for jobs 246201,246239,246240,246242,246243,246244,246245
date --iso-8601=seconds
echo "=== SACCT ==="
sacct -X -n -P -j 246201,246239,246240,246242,246243,246244,246245 --format=JobID,JobName,State,ExitCode,Elapsed,NodeList 2>&1
echo "=== SQUEUE ==="
squeue -j 246201,246239,246240,246242,246243,246244,246245 -h -o '%i|%T|%R|%S' 2>&1
echo '=== DEPENDENCY CHECK ==='
scontrol show job 246244 2>/dev/null | grep -oE 'Dependency=[^ ]*' | head -1
scontrol show job 246245 2>/dev/null | grep -oE 'Dependency=[^ ]*' | head -1
cat /data1/home/sunyiq/ohn_da_vs_ar_531_20261021/results/p1b/p1b_selection.json 2>/dev/null
echo '=== A1 SMOKE SPEED ==='
tr '' '
' < /data1/home/sunyiq/ohn_da_vs_ar_531_20261021/logs/ohn_a1_smoke-246201.err 2>/dev/null | grep -oE '[0-9]+/[0-9]+ \[[0-9:]+<[0-9:]+, *[0-9.]+(it/s|s/it)\]' | tail -3
grep -hE 'Epoch 1 |update|Loading|took' /data1/home/sunyiq/ohn_da_vs_ar_531_20261021/runs_smoke/a1_smoke_2210_121434/output.log 2>/dev/null | head -8
grep -h 'Epoch' /data1/home/sunyiq/openhydronet_531_20261015/runs/id18_nse_s101_1610_225041/output.log 2>/dev/null | head -3
grep -h 'Epoch' /data1/home/sunyiq/openhydronet_531_20261015/runs/id18_nse_s101_1610_225041/output.log 2>/dev/null | tail -2
echo "=== RESERVATIONS ==="
scontrol show reservation 2>&1 | grep -E "ReservationName|StartTime|Nodes=|Flags" | head -12
echo "=== LOG MARKERS ==="
for f in "/data1/home/sunyiq/ohn_da_vs_ar_531_20261021"/logs/ohn_a1_smoke-246201.out "/data1/home/sunyiq/ohn_da_vs_ar_531_20261021"/logs/ohn_a1_smoke-246201.err "/data1/home/sunyiq/ohn_da_vs_ar_531_20261021"/logs/ohn_da_select-246240.out "/data1/home/sunyiq/ohn_da_vs_ar_531_20261021"/logs/ohn_da_select-246240.err "/data1/home/sunyiq/ohn_da_vs_ar_531_20261021"/logs/ohn_p3_score-246245.out "/data1/home/sunyiq/ohn_da_vs_ar_531_20261021"/logs/ohn_p3_score-246245.err; do [ -f "$f" ] && { echo "--- $(basename $f)"; grep -hE 'A1_TRAIN_50_UPDATES_S|SMOKE_A1_DONE|SELECTED|SELECT_DONE|VERDICTS|P3_DONE|mean_L1_3|Traceback|Error|FATAL|CONDA_FAILED|MISSING|SUBMIT_FAILED' "$f" | tail -6; }; done
echo END_STATUS
