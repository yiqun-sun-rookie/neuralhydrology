#!/bin/bash
# nature1st-attr-swap seq=6 -- STATUS ONLY for jobs 206175 (control) / 206176 (treatment).
# Replaces the seq=5 remedy, which contained an sbatch and would have resubmitted a
# duplicate pair if it were ever re-run. Nothing here submits, deletes or edits.
set -o pipefail
RUN=/data1/home/sunyiq/nature_1st
CTRL=206175
TREAT=206176

echo "=== A. JOB STATE ==="
sacct -j $CTRL,$TREAT -X --format=JobID%10,JobName%22,State%14,ExitCode%8,Elapsed%12,NodeList%9 2>&1

echo "=== B. NODE + GPU ==="
for j in $CTRL $TREAT; do
    f=$(ls "$RUN"/logs/attr_swap/*-${j}.out 2>/dev/null | head -1)
    echo "--- $j : ${f:-no log yet} ---"
    [ -n "$f" ] && head -3 "$f" 2>&1
done

echo "=== C. FATAL / crash ==="
for j in $CTRL $TREAT; do
    f=$(ls "$RUN"/logs/attr_swap/*-${j}.err 2>/dev/null | head -1)
    [ -n "$f" ] && { echo "--- $j ---"; grep -E 'FATAL|Error|Traceback|error:' "$f" 2>/dev/null | head -5 || echo "clean"; }
done

echo "=== D. TRAINING PROGRESS ==="
for j in $CTRL $TREAT; do
    f=$(ls "$RUN"/logs/attr_swap/*-${j}.out 2>/dev/null | head -1)
    if [ -n "$f" ]; then
        echo "--- $j ---"
        grep -E 'val_median_NSE|Best median NSE|Train samples|Model:|Done\.' "$f" 2>/dev/null | tail -8 || true
    fi
done

echo "=== E. FINAL METRICS IF DONE ==="
for d in q_lstm_control_hpc_s42 q_lstm_hydroatlas_hpc_s42; do
    echo "--- $d ---"
    cat "$RUN/models/$d/best_metrics.json" 2>/dev/null || echo "(not finished)"
done
echo "=== END seq=6 (status only) ==="
