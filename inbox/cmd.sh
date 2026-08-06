#!/bin/bash
# seq=4 — 补查：坏节点真实状态 + 那批 FAILED 作业的死因。只读。

echo "=== 1 ALL GPU NODES FULL STATE ==="
sinfo -N -o "%12N %12P %10T %5c %10G %30E" 2>&1 | grep -E "NODELIST|ngu"

echo; echo "=== 2 DOWN / DRAIN / RESERVED NODES (any) ==="
sinfo -R 2>&1 | head -20
echo "--- (empty above means no node is down/drained) ---"

echo; echo "=== 3 THE FAILED BATCH 157838-157847 ==="
sacct -j 157838,157839,157840,157841,157842,157843,157847 \
  --format=JobID%12,JobName%18,Partition%9,NodeList%12,State%20,ExitCode%9,Start%20,Elapsed%10 2>&1

echo; echo "=== 4 hgpu2p FAILURES DETAIL ==="
sacct -j 157876,157878,157881,157888,157908 \
  --format=JobID%12,JobName%18,NodeList%12,State%20,ExitCode%9,Elapsed%10,Comment%25 2>&1

echo; echo "=== 5 LAST COMPLETED JOB (reference) ==="
sacct -j 157494,157907 \
  --format=JobID%12,JobName%20,Partition%9,NodeList%12,AllocTRES%30,Elapsed%12,State%12 2>&1

echo; echo "=== 6 PARTITION LIMITS (real) ==="
scontrol show partition hgpu2p 2>&1 | head -20

echo; echo "=== 7 QOS / ACCOUNT LIMITS ==="
sacctmgr -n show assoc where user=$USER format=Account%16,Partition%12,QOS%20,MaxJobs%8,MaxSubmit%10,GrpTRES%25 2>&1 | head -15

echo; echo "=== 8 SLURM LOG DIR HINT ==="
ls -lt ~/neuralhydrology/logs/ 2>/dev/null | head -8
