#!/bin/bash
# a02 seq=12 : are the GPUs actually busy, or is ExcNodeList=ngu002 the blocker?
export LC_ALL=C

echo "=== A GPU ALLOC PER NODE (configured vs used) ==="
sinfo -p hgpu2p -N -O "NodeHost:10,StateLong:10,Gres:14,GresUsed:18,CPUsState:16" 2>&1 | head -14

echo "=== B FULL NODE DETAIL FOR TWO NODES ==="
scontrol show node ngu001 2>&1 | tr ' ' '\n' | grep -E "^(NodeName|State|CfgTRES|AllocTRES|Gres)" | sed 's/^/  ngu001 /'
scontrol show node ngu002 2>&1 | tr ' ' '\n' | grep -E "^(NodeName|State|CfgTRES|AllocTRES|Gres|Reason)" | sed 's/^/  ngu002 /'

echo "=== C EVERY JOB ON THE CLUSTER USING GPUs (all users, all partitions) ==="
squeue -t R -O "JobID:9,UserName:10,Partition:9,NodeList:12,tres-per-node:12,TimeUsed:10,Name:18" 2>&1 | head -20

echo "=== D WHAT DOES SLURM SAY IF I ASK IT TO TEST-SCHEDULE ONE JOB ==="
scontrol show job 201681 2>&1 | tr ' ' '\n' | grep -E "^(Reason|StartTime|Priority|TresPerNode|NumCPUs|TimeLimit|ExcNodeList)" | sed 's/^/  /'

echo "=== E DOES A SHORT JOB WITHOUT THE EXCLUDE GET A BETTER START TIME? (test only, not submitted) ==="
sbatch --test-only -p hgpu2p -N1 -n1 --cpus-per-task=4 --gres=gpu:1 -t 10:00:00 \
       --wrap="echo test" 2>&1 | head -3
echo "--- same but excluding ngu002 ---"
sbatch --test-only -p hgpu2p -N1 -n1 --cpus-per-task=4 --gres=gpu:1 -t 10:00:00 \
       --exclude=ngu002 --wrap="echo test" 2>&1 | head -3
echo "--- same but 30h like our real jobs ---"
sbatch --test-only -p hgpu2p -N1 -n1 --cpus-per-task=4 --gres=gpu:1 -t 30:00:00 \
       --exclude=ngu002 --wrap="echo test" 2>&1 | head -3

echo "=== F PARTITION LIMITS ==="
scontrol show partition hgpu2p 2>&1 | tr ' ' '\n' | grep -E "^(PartitionName|MaxTime|DefaultTime|MaxNodes|TotalCPUs|TotalNodes|State|QoS|MaxCPUsPerNode)" | sed 's/^/  /'
