#!/bin/bash
# read-only status for jobs 246240,246243,246279,246280,246281
date --iso-8601=seconds
echo "=== SACCT ==="
sacct -X -n -P -j 246240,246243,246279,246280,246281 --format=JobID,JobName,State,ExitCode,Elapsed,NodeList 2>&1
echo "=== SQUEUE ==="
squeue -j 246240,246243,246279,246280,246281 -h -o '%i|%T|%R|%S' 2>&1
echo '=== DEPENDENCY CHECK ==='
scontrol show job 246280 2>/dev/null | grep -oE 'Dependency=[^ ]*' | head -1
scontrol show job 246281 2>/dev/null | grep -oE 'Dependency=[^ ]*' | head -1
echo '=== P1B ==='
cat /data1/home/sunyiq/ohn_da_vs_ar_531_20261021/results/p1b/p1b_selection.json 2>/dev/null
cat /data1/home/sunyiq/ohn_da_vs_ar_531_20261021/results/p1b/p1b_grid_scores.csv 2>/dev/null
echo '=== DA STAMPS ==='
for f in /data1/home/sunyiq/ohn_da_vs_ar_531_20261021/copies/p2/*/*/da_eval_stamp_*.json; do [ -f "$f" ] && echo "$f $(grep -oE '"elapsed_s": [0-9.]+' $f)"; done 2>/dev/null | sed 's#.*/copies/p2/##' | head -20
echo '=== A1 EPOCHS ==='
for d in /data1/home/sunyiq/ohn_da_vs_ar_531_20261021/runs/a1_s10*; do [ -d "$d" ] && echo "$(basename $d) $(grep -c 'average loss' $d/output.log 2>/dev/null) epochs, last: $(grep 'average loss' $d/output.log 2>/dev/null | tail -1 | cut -c1-40)"; done
echo "=== RESERVATIONS ==="
scontrol show reservation 2>&1 | grep -E "ReservationName|StartTime|Nodes=|Flags" | head -12
echo "=== LOG MARKERS ==="
for f in "/data1/home/sunyiq/ohn_da_vs_ar_531_20261021"/logs/ohn_da_select-246240.out "/data1/home/sunyiq/ohn_da_vs_ar_531_20261021"/logs/ohn_da_select-246240.err "/data1/home/sunyiq/ohn_da_vs_ar_531_20261021"/logs/ohn_p3_score-246281.out "/data1/home/sunyiq/ohn_da_vs_ar_531_20261021"/logs/ohn_p3_score-246281.err; do [ -f "$f" ] && { echo "--- $(basename $f)"; grep -hE 'A1_TRAIN_50_UPDATES_S|SMOKE_A1_DONE|SELECTED|SELECT_DONE|VERDICTS|P3_DONE|mean_L1_3|Traceback|Error|FATAL|CONDA_FAILED|MISSING|SUBMIT_FAILED' "$f" | tail -6; }; done
echo END_STATUS
