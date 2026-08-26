#!/bin/bash
# Read-only survey: what capacity actually exists, and why everything is pending.
set -o pipefail

echo "=== A. ALL PARTITIONS ==="
sinfo -o "%.10P %.6a %.12l %.6D %.6t %.30N" 2>&1 || true

echo "=== B. NODE DETAIL (gres, cpus, state) ==="
sinfo -N -o "%.10N %.10P %.10T %.5c %.14G %.30E" 2>&1 | head -40 || true

echo "=== C. WHO IS RUNNING WHAT ==="
echo "  -- all running jobs, cluster wide --"
squeue -t RUNNING -o "%.14i %.10u %.14j %.10P %.12L %.10M %.8D %.20R" 2>&1 | head -30 || true
echo "  -- running count by user --"
squeue -t RUNNING -h -o "%u" 2>/dev/null | sort | uniq -c | sort -rn | head || true
echo "  -- pending count by user --"
squeue -t PENDING -h -o "%u" 2>/dev/null | sort | uniq -c | sort -rn | head || true

echo "=== D. MY PENDING JOBS AND WHY ==="
squeue -u "$USER" -t PENDING -o "%.20i %.14j %.10P %.12r %.20S" 2>&1 | head -20 || true

echo "=== E. MY LIMITS ==="
sacctmgr -n -P show assoc user="$USER" format=Account,Partition,GrpTRES,MaxJobs,MaxSubmit,GrpJobs,QOS 2>&1 | head -20 || echo "  (sacctmgr not readable)"
scontrol show partition 2>/dev/null | grep -E 'PartitionName|MaxTime|TotalNodes|TotalCPUs|State=' | head -40 || true

echo "=== F. GRES DETAIL PER NODE (does it name the card?) ==="
for n in ngu001 ngu003 ngu101 ngu201; do
  echo "  -- $n --"
  scontrol show node "$n" 2>/dev/null | grep -E 'NodeName|Gres=|CfgTRES|State=|OS=' | sed 's/^/    /' || echo "    (unreadable)"
done

echo "=== G. NODE TEST LAUNCHER AVAILABLE? ==="
ls -l /data1/home/sunyiq/hpc_mailbox/inbox/node_test.slurm 2>&1 || echo "  absent"

echo "=== H. DONE ==="
