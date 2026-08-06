#!/bin/bash
# probe seq=4 — 查清 hgpu8 为何排到 2027：谁占着 GPU？
cd ~/hpc_mailbox || exit 1

echo "=== 1. scontrol show node (raw, no grep) ==="
scontrol show node ngu201 2>&1 | head -20

echo; echo "=== 2. ALL jobs on these nodes, any state, any user ==="
squeue -w ngu201,ngu202,ngu203 -o "%8i %10u %9P %8T %6D %14b %10M %10l" 2>&1

echo; echo "=== 3. Partition-wide, all states ==="
squeue -p hgpu8 -o "%8i %10u %8T %14b %10M %10l %10R" 2>&1

echo; echo "=== 4. GRES detail via sinfo ==="
sinfo -p hgpu8 -o "%12N %10T %20C %15G %20A" 2>&1

echo; echo "=== 5. Does the partition allow me at all? ==="
scontrol show partition hgpu8 2>&1 | tr ' ' '\n' | grep -E "AllowGroups|AllowAccounts|AllowQos|MaxTime|DefaultTime|TotalNodes|State|PriorityTier|OverSubscribe|MaxCPUsPerNode" | sed 's/^/  /'

echo; echo "=== 6. My QOS limits ==="
sacctmgr -n show qos qos_sunyiq format=Name%14,MaxTRES%30,MaxJobsPU%10,MaxSubmitPU%12,GrpTRES%25 2>&1

echo; echo "=== 7. Compare: hgpu2p partition config ==="
scontrol show partition hgpu2p 2>&1 | tr ' ' '\n' | grep -E "AllowGroups|AllowAccounts|AllowQos|MaxTime|TotalNodes|State|MaxCPUsPerNode" | sed 's/^/  /'
