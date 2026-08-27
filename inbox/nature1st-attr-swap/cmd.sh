#!/bin/bash
# nature1st-attr-swap seq=101 -- READ-ONLY. armJ is alone in the hgpu2p queue yet
# still PENDING(Priority) with a start estimate two days out. Find the real constraint,
# and read the GPU model out of an old node-test log.
set -o pipefail
date "+wallclock %F %T %z"

echo "=== A. GPU MODEL FROM THE OLD NODE TEST ==="
f=/data1/home/sunyiq/hpc_mailbox/outbox/slurm_201451.out
[ -f "$f" ] && { echo "-- $f --"; grep -E "NVIDIA-SMI|Driver|GeForce|RTX|A100|A800|V100|Tesla|hostname|Node|^\|" "$f" 2>/dev/null | head -18 || true; } || echo "  (missing)"
echo '-- which node did that test run on --'
sacct -j 201451 -X --format=JobID%10,JobName%18,State%12,NodeList%9,End%18 2>&1 | head -4

echo "=== B. WHY WONT armJ START? ==="
echo '-- my running jobs cluster-wide, by partition --'
squeue -u $USER -t RUNNING -o '%.11i %.10P %.16j %.9N %.10M' 2>&1 | head -20
echo '-- count --'
squeue -u $USER -t RUNNING -h 2>&1 | wc -l
echo '-- priority breakdown for armJ (sprio) --'
sprio -j 215195 2>&1 | head -5 || echo '  (sprio unavailable)'
echo '-- my association limits (max jobs / max gpus?) --'
sacctmgr -n show assoc user=$USER format=Account,Partition,GrpTRES%30,MaxJobs,MaxSubmit,GrpJobs,QOS%25 2>&1 | head -12 || true
echo '-- qos limits --'
sacctmgr -n show qos format=Name,MaxJobsPU,MaxSubmitPU,MaxTRESPU%30,GrpTRES%25 2>&1 | head -10 || true

echo "=== C. PARTITION CONFIG (hgpu2p vs hgpu2) ==="
for p in hgpu2p hgpu2 hgpu4; do
  echo "-- $p --"
  scontrol show partition $p 2>&1 | grep -E 'PartitionName|AllowGroups|AllowAccounts|MaxNodes|MaxTime|State=|TotalNodes|Nodes=|PriorityTier|QoS' | head -6 || true
done

echo "=== D. WHO HOLDS THE hgpu2p GPUs RIGHT NOW ==="
squeue -w ngu001,ngu004,ngu005,ngu006,ngu007,ngu008,ngu010,ngu011 -o '%.11i %.9u %.10P %.16j %.9T %.10M %.9N' 2>&1 | head -20
echo "=== END seq=101 ==="
