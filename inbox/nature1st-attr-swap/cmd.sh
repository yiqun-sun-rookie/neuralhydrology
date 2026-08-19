#!/bin/bash
# nature1st-attr-swap seq=2
# Jobs 205848 / 205854 both landed on ngu002 (the documented bad node), reported
# CUDA False, and silently fell back to CPU -- they would take weeks, not hours.
# This kills them, installs the patched sbatch scripts (in-script --exclude=ngu002
# plus a fail-fast GPU check), and resubmits. User authorised both submissions.
set -o pipefail
CH=nature1st-attr-swap
RUN=/data1/home/sunyiq/nature_1st

echo "=== A. CANCEL the CPU-fallback jobs ==="
scancel 205848 205854 2>&1
sleep 5
sacct -j 205848,205854 -X --format=JobID%10,State%14,Elapsed%10,NodeList%9 2>&1

echo "=== B. INSTALL patched scripts ==="
cp -v ~/hpc_mailbox/inbox/$CH/hpc_train_q_control.sbatch "$RUN/scripts/" 2>&1
cp -v ~/hpc_mailbox/inbox/$CH/hpc_train_q_hydroatlas.sbatch "$RUN/scripts/" 2>&1
sed -i 's/\r$//' "$RUN"/scripts/hpc_train_q_*.sbatch 2>&1
echo "-- exclude directive present? (want 1 and 1) --"
grep -c 'exclude=ngu002' "$RUN"/scripts/hpc_train_q_control.sbatch "$RUN"/scripts/hpc_train_q_hydroatlas.sbatch 2>&1 || true
echo "-- GPU fail-fast present? --"
grep -c 'no usable GPU' "$RUN"/scripts/hpc_train_q_control.sbatch "$RUN"/scripts/hpc_train_q_hydroatlas.sbatch 2>&1 || true

echo "=== C. SUBMIT ==="
cd "$RUN" || exit 1
mkdir -p logs/attr_swap
JIDS=""
for arm in control hydroatlas; do
    out=$(sbatch scripts/hpc_train_q_${arm}.sbatch 2>&1)
    echo "[$arm] $(echo "$out" | grep -E 'Submitted batch job [0-9]+' || echo "NO JOB ID -- submission rejected")"
    jid=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+$')
    if [ -z "$jid" ]; then echo "[$arm] SUBMIT_FAILED; full output:"; echo "$out" | head -20; else JIDS="$JIDS $jid"; fi
done
echo "jids=$JIDS"

echo "=== D. WAIT 3 min, then verify node + GPU ==="
sleep 180
for j in $JIDS; do
    sacct -j "$j" -X --format=JobID%10,JobName%22,State%14,ExitCode%8,Elapsed%10,NodeList%9 2>&1 | tail -2
done
echo "-- log heads (must NOT say CUDA False) --"
for f in $(ls -t "$RUN"/logs/attr_swap/*.out 2>/dev/null | head -2); do
    echo "--- $f ---"; head -4 "$f" 2>&1
done
echo "-- any FATAL? --"
grep -l 'FATAL' "$RUN"/logs/attr_swap/*.err 2>/dev/null || echo "none"
echo "=== END seq=2 ==="
