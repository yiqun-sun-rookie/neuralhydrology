#!/bin/bash
cd ~/hpc_mailbox || exit 1
mkdir -p outbox
echo "=== SUBMIT ==="
JID=$(sbatch --parsable inbox/autoresearch-64/databases.slurm 2>&1)
echo "jobid=$JID"
echo "=== WAIT (max 15 min) ==="
for i in $(seq 1 90); do
    LEFT=$(squeue -j "$JID" -h -o "%i" 2>/dev/null | wc -l)
    [ $((i % 6)) -eq 0 ] && echo "t=$((i*10))s left=$LEFT"
    [ "$LEFT" -eq 0 ] && break
    sleep 10
done
echo "=== RESULT ==="
sacct -j "$JID" -X --format=JobID%10,JobName%14,NodeList%9,State%14,ExitCode%8,Elapsed%10 2>&1
echo "---- stdout ----"
cat outbox/slurm_${JID}.out 2>/dev/null | tail -70
echo "---- stderr (tail) ----"
cat outbox/slurm_${JID}.err 2>/dev/null | tail -15
rm -f outbox/slurm_*.out outbox/slurm_*.err
