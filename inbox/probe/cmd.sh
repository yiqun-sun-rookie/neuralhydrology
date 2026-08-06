#!/bin/bash
# probe seq=2 — 给 ngu201/ngu203 排队。提交后立即返回，不占 worker。
cd ~/hpc_mailbox || exit 1

echo "=== hgpu8 CURRENT LOAD ==="
sinfo -p hgpu8 -N -o "%12N %10T %6C %10G" 2>&1
echo "--- who is on hgpu8 ---"
squeue -p hgpu8 -o "%8i %10u %8T %12M %12l %8N" 2>&1 | head -12

echo; echo "=== SUBMIT (no wait) ==="
for N in ngu201 ngu203; do
    JID=$(sbatch --parsable -p hgpu8 --nodelist=$N --job-name=nt_$N -t 00:04:00 inbox/node_test.slurm 2>&1)
    echo "$N -> $JID"
done

echo; echo "=== MY QUEUE ==="
squeue -u "$USER" -o "%10i %12j %9P %8T %10M %20R" 2>&1
