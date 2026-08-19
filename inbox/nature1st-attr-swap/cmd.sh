#!/bin/bash
# nature1st-attr-swap seq=5
# 205886 (ngu004) and 205887 (ngu008) both died after ~25 s with exit 1, on GOOD
# nodes with CUDA True. Hypothesis: the aborted ngu002 CPU jobs (205848 / 205854)
# already created models/q_lstm_*_hpc_s42, and the scripts pass
# --require_empty_output_dir, so the trainer refuses to start.
# Remedy is applied ONLY if the logs confirm that cause. Nothing is deleted --
# the stale dirs are renamed, so the evidence survives.
set -o pipefail
RUN=/data1/home/sunyiq/nature_1st

echo "=== A. WHY THEY FAILED (stderr tails) ==="
for j in 205886 205887; do
    f=$(ls "$RUN"/logs/attr_swap/*-${j}.err 2>/dev/null | head -1)
    echo "--- $j : ${f:-none} ---"
    [ -n "$f" ] && tail -20 "$f" 2>&1
done

echo "=== B. stdout tails ==="
for j in 205886 205887; do
    f=$(ls "$RUN"/logs/attr_swap/*-${j}.out 2>/dev/null | head -1)
    echo "--- $j ---"; [ -n "$f" ] && tail -6 "$f" 2>&1
done

echo "=== C. LEFTOVER OUTPUT DIRS ==="
ls -la "$RUN"/models/ 2>&1 | head -12

echo "=== D. REMEDY ==="
if grep -qiE 'not empty|already exists|require_empty|output directory' "$RUN"/logs/attr_swap/*-20588[67].err 2>/dev/null; then
    echo "CONFIRMED: non-empty output directory. Renaming (not deleting) and resubmitting."
    mv -v "$RUN/models/q_lstm_control_hpc_s42"    "$RUN/models/_aborted_cpu_ngu002_control_205848"    2>&1
    mv -v "$RUN/models/q_lstm_hydroatlas_hpc_s42" "$RUN/models/_aborted_cpu_ngu002_treatment_205854" 2>&1
    cd "$RUN" || exit 1
    for arm in control hydroatlas; do
        out=$(sbatch scripts/hpc_train_q_${arm}.sbatch 2>&1)
        echo "[$arm] $(echo "$out" | grep -E 'Submitted batch job [0-9]+' || echo 'NO JOB ID -- REJECTED')"
        echo "$out" | grep -qE 'Submitted batch job [0-9]+' || { echo "[$arm] full output:"; echo "$out" | head -15; }
    done
    echo "-- queue --"
    squeue -u sunyiq -o "%.10i %.24j %.9P %.8T %.10M %R" 2>&1 | grep -E 'JOBID|q_ctrl|q_treat' || true
else
    echo "NOT the output-dir cause. No action taken -- the stderr above needs a human read."
fi
echo "=== END seq=5 ==="
