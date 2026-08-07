#!/bin/bash
# a02 seq=11 : why are all 12 jobs PENDING(Priority)? real capacity vs limits.
export LC_ALL=C

echo "=== A CLUSTER-WIDE hgpu2p QUEUE (all users) ==="
squeue -p hgpu2p -o "%.10i %.10u %.16j %.8T %.6D %.12b %.10M %.18R" 2>&1 | head -22

echo "=== B GPU ALLOCATION PER NODE ==="
sinfo -p hgpu2p -N -o "  %10N %8t %12C %20G %30E" 2>&1 | head -14
echo "--- gres detail (alloc/total) ---"
scontrol show node ngu001 ngu004 ngu005 ngu006 2>/dev/null | grep -E "NodeName|CfgTRES|AllocTRES|State=" | sed 's/^/  /' | head -20

echo "=== C WHY IS MY FIRST JOB WAITING (authoritative reason) ==="
scontrol show job 201681 2>&1 | grep -E "JobId|JobState|Reason|Priority|NumCPUs|TresPerNode|Partition|ExcNodeList|StartTime" | sed 's/^/  /'

echo "=== D ACCOUNT LIMITS (is there a per-user cap?) ==="
sacctmgr -n show assoc user=$USER format=Account,User,Partition,MaxJobs,MaxSubmit,GrpTRES,MaxTRES 2>&1 | head -10
echo "--- qos ---"
sacctmgr -n show qos format=Name,MaxJobsPU,MaxSubmitPU,MaxTRESPU,GrpTRES 2>&1 | head -8

echo "=== E MY PRIORITY VS QUEUE ==="
squeue -p hgpu2p -o "%.10i %.10u %.8T %.12p %.16j" --sort=-p 2>&1 | head -14
