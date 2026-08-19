#!/bin/bash
# nature1st-attr-swap seq=3 -- STATUS ONLY. Supersedes seq=2 (which would have
# resubmitted). The user already resubmitted manually at 20:5x:
#   205886 = control (12 US-only attributes)
#   205887 = treatment (13 HydroATLAS global attributes)
# Both carry #SBATCH --exclude=ngu002. This command MUST NOT submit anything --
# a duplicate pair would silently double the machine-hour bill.
set -o pipefail
RUN=/data1/home/sunyiq/nature_1st

echo "=== A. JOB STATE ==="
sacct -j 205886,205887 -X --format=JobID%10,JobName%22,State%14,ExitCode%8,Elapsed%12,NodeList%9 2>&1

echo "=== B. NODE + GPU (must NOT say CUDA False) ==="
for j in 205886 205887; do
    f=$(ls "$RUN"/logs/attr_swap/*-${j}.out 2>/dev/null | head -1)
    echo "--- $j : ${f:-no log yet} ---"
    [ -n "$f" ] && head -3 "$f" 2>&1
done

echo "=== C. FATAL / GPU-guard trips ==="
grep -h 'FATAL' "$RUN"/logs/attr_swap/*-20588*.err 2>/dev/null | head -5 || echo "none"

echo "=== D. TRAINING PROGRESS (epoch lines) ==="
for j in 205886 205887; do
    f=$(ls "$RUN"/logs/attr_swap/*-${j}.out 2>/dev/null | head -1)
    if [ -n "$f" ]; then
        echo "--- $j ---"
        grep -E '^(Epoch|\[.*\] Epoch)' "$f" 2>/dev/null | tail -6 || true
        grep -E 'val_median_NSE|Best median NSE|Done\.' "$f" 2>/dev/null | tail -6 || true
    fi
done

echo "=== E. RESULTS IF FINISHED ==="
for d in q_lstm_control_hpc_s42 q_lstm_hydroatlas_hpc_s42; do
    echo "--- $d ---"
    cat "$RUN/models/$d/best_metrics.json" 2>/dev/null || echo "(not finished)"
done
echo "=== END seq=3 (status only, nothing submitted) ==="
