#!/bin/bash
cd ~/hpc_mailbox || exit 1
mkdir -p outbox
rm -f ~/autoresearch64/runs/unified_autoresearch/VERIFICATION_64_HPC.json
echo "=== SUBMIT ==="
JID=$(sbatch --parsable inbox/autoresearch-64/databases.slurm 2>&1)
echo "jobid=$JID"
for i in $(seq 1 90); do
    LEFT=$(squeue -j "$JID" -h -o "%i" 2>/dev/null | wc -l)
    [ "$LEFT" -eq 0 ] && break
    sleep 10
done
echo "=== RESULT ==="
sacct -j "$JID" -X --format=JobID%10,State%14,ExitCode%8,Elapsed%10 2>&1
cat outbox/slurm_${JID}.out 2>/dev/null | tail -60
echo "---- stderr ----"; cat outbox/slurm_${JID}.err 2>/dev/null | tail -10
rm -f outbox/slurm_*.out outbox/slurm_*.err
