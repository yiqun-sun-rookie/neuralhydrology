#!/bin/bash
# ID29 seq=4: submit the HPC environment smoke job (6 basins, 1 epoch, all three arms).
# User approved running this reproduction on HPC.
cd ~/hpc_mailbox || exit 1
mkdir -p outbox

echo "=== SUBMIT ==="
JID=$(sbatch --parsable inbox/id29_smoke.slurm 2>&1)
echo "jobid=$JID"

echo "=== WAIT (max 12 min) ==="
for i in $(seq 1 72); do
    ST=$(squeue -j "$JID" -h -o "%t" 2>/dev/null)
    [ -z "$ST" ] && break
    [ $((i % 6)) -eq 0 ] && echo "  t=$((i*10))s state=$ST"
    sleep 10
done

echo "=== SACCT ==="
sacct -j "$JID" -X --format=JobID%10,JobName%12,NodeList%9,State%12,ExitCode%8,Elapsed%10 2>&1

echo "=== STDOUT ==="
tail -45 outbox/slurm_${JID}.out 2>/dev/null

echo "=== STDERR (tail) ==="
tail -20 outbox/slurm_${JID}.err 2>/dev/null

rm -f outbox/slurm_*.out outbox/slurm_*.err
