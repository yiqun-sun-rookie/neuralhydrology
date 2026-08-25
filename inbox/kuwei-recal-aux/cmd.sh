#!/bin/bash
# SHORT diagnostic only. No sleep loops (a previous long wait blocked the whole mailbox).
set -o pipefail
echo "=== A. why is the gate pending? ==="
scontrol show job 212027 2>&1 | grep -E 'JobId|JobState|Reason|Partition|NumCPUs|TimeLimit|Priority|QOS|NodeList' | head -12 || true
echo "=== B. my queue ==="
squeue -u ${USER} -o "%.10i %.14j %.12P %.8T %.10M %.6D %R" 2>&1 | head -12 || true
echo "=== C. account limits ==="
sacctmgr -n show assoc user=${USER} format=Account,Partition,QOS,MaxJobs,MaxSubmit,GrpTRES,MaxTRES 2>&1 | head -10 || echo "(sacctmgr unavailable)"
echo "=== D. partition state right now ==="
sinfo -p hcpu48 -o "%20P %10a %12l %6D %10t %N" 2>&1 | head -8 || true
echo "=== E. what the successful probe used ==="
sacct -j 211961 --format=JobID,Partition,ReqCPUS,Timelimit,State,Elapsed,NodeList%10 2>&1 | head -4 || true
echo "=== F. gate job resources as submitted ==="
sacct -j 212027 --format=JobID,Partition,ReqCPUS,Timelimit,State,Reason%30 2>&1 | head -4 || true
echo "=== DONE ==="
