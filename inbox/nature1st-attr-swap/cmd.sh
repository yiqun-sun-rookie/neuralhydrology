#!/bin/bash
# nature1st-attr-swap seq=15 -- SUBMIT the two stream-network ablation arms.
# User authorised both GPU submissions (2026-08-20).
#   arm C  scripts/hpc_train_q_us_minus_network.sbatch       -> models/q_lstm_usminus4_hpc_s42
#   arm D  scripts/hpc_train_q_hydroatlas_plus_network.sbatch -> models/q_lstm_globalplus4_hpc_s42
# Payload verified intact in seq=14 (statsC 8c2d69fe08fe4efc / statsD 81372304d67d2669 /
# metaD 0b0fb44e4b8a2711). This cmd.sh MUST be superseded by a status-only one right
# after it runs -- a daemon restart re-scans the channel and would resubmit.
set -o pipefail
RUN=/data1/home/sunyiq/nature_1st

echo "=== A. GUARD: output dirs must still be absent ==="
BLOCK=0
for d in q_lstm_usminus4_hpc_s42 q_lstm_globalplus4_hpc_s42; do
    if [ -e "$RUN/models/$d" ]; then echo "PRESENT $d -- refusing to submit"; BLOCK=1; fi
done
[ "$BLOCK" -eq 0 ] || { echo "ABORT: stale output dir(s) present"; exit 1; }

echo "=== B. SUBMIT ==="
cd "$RUN" || exit 1
mkdir -p logs/attr_swap
JIDS=""
for arm in us_minus_network hydroatlas_plus_network; do
    out=$(sbatch scripts/hpc_train_q_${arm}.sbatch 2>&1)
    line=$(echo "$out" | grep -E 'Submitted batch job [0-9]+' || echo "NO JOB ID -- submission rejected")
    echo "[$arm] $line"
    jid=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+$' || true)
    if [ -z "$jid" ]; then
        echo "[$arm] SUBMIT_FAILED; first 20 lines of wrapper output:"
        echo "$out" | head -20
    else
        JIDS="$JIDS $jid"
    fi
done
echo "jids=$JIDS"

echo "=== C. WAIT 4 min, then verify node + GPU (must NOT say CUDA False) ==="
sleep 240
for j in $JIDS; do
    sacct -j "$j" -X --format=JobID%10,JobName%24,State%12,ExitCode%8,Elapsed%10,NodeList%9 2>&1 | tail -2
done
echo "-- newest arm C / arm D logs --"
for f in $(ls -t "$RUN"/logs/attr_swap/armC_usminus4-*.out "$RUN"/logs/attr_swap/armD_globalplus4-*.out 2>/dev/null | head -2); do
    echo "--- $f ---"; head -12 "$f" 2>&1
done
echo "-- guard lines (want: 8 US attributes / 17 attributes) --"
grep -h '\[guard\]' "$RUN"/logs/attr_swap/armC_usminus4-*.out "$RUN"/logs/attr_swap/armD_globalplus4-*.out 2>/dev/null | head -6 || true
echo "-- any FATAL / traceback? --"
grep -l 'FATAL\|Traceback' "$RUN"/logs/attr_swap/armC_usminus4-*.err "$RUN"/logs/attr_swap/armD_globalplus4-*.err 2>/dev/null || echo "none"

echo "=== END seq=15 ==="
