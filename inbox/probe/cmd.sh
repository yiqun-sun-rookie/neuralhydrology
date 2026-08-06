#!/bin/bash
# probe seq=3 — 取消重复作业 + 查清 hgpu8 到底卡在哪
cd ~/hpc_mailbox || exit 1

echo "=== 1. CANCEL MY DUPLICATES (keep the older 201433/201435) ==="
scancel 201452 201453 2>&1 && echo "cancelled 201452 201453"

echo; echo "=== 2. GPU ALLOCATION PER NODE (this is the real constraint) ==="
scontrol show node ngu201 ngu202 ngu203 2>&1 | grep -E "NodeName|CfgTRES|AllocTRES|State=" | sed 's/^ */  /'

echo; echo "=== 3. ALL JOBS ON hgpu8 (everyone, not just me) ==="
squeue -p hgpu8 -t RUNNING -o "%8i %10u %6D %20b %12M %12l %8N" 2>&1

echo; echo "=== 4. WHY IS MINE PENDING ==="
for J in 201433 201435; do
    echo "--- job $J ---"
    scontrol show job $J 2>&1 | grep -E "JobState|Reason|TRES=|StartTime|Priority" | sed 's/^ */  /'
done

echo; echo "=== 5. ESTIMATED START (backfill) ==="
squeue -u "$USER" --start -o "%10i %12j %9P %20S %20R" 2>&1

echo; echo "=== 6. HOW LONG HAVE THEY WAITED ==="
squeue -u "$USER" -o "%10i %12j %8T %14V %12M %20R" 2>&1
