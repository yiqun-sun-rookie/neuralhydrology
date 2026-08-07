#!/bin/bash
# a02 seq=16 : hgpu2p is exhausted by a cluster-wide GRES accounting leak.
# ngu009 (hgpu2) passed a real CUDA test, so the environment is fine -- we just
# need capacity. Widen the 12 pending jobs to every GPU partition so they start
# wherever a slot frees up first. Nothing else about the jobs changes.
export LC_ALL=C
PARTS=hgpu2p,hgpu2,hgpu4,hgpu8

echo "=== A WIDEN PARTITION FOR THE 12 A02 JOBS ==="
for JID in 201681 201682 201683 201684 201685 201686 201687 201688 201689 201690 201691 201692; do
  OUT=$(scontrol update jobid=$JID partition=$PARTS 2>&1)
  if [ -z "$OUT" ]; then
    echo "  $JID -> $PARTS"
  else
    echo "  $JID FAILED: $OUT"
  fi
done

echo "=== B CONFIRM ==="
scontrol show job 201681 2>&1 | tr ' ' '\n' | grep -E "^(JobId|Partition|Reason|ExcNodeList|TimeLimit)" | sed 's/^/  /'

echo "=== C WAIT 3 MIN FOR THE SCHEDULER ==="
sleep 180

echo "=== D QUEUE NOW ==="
squeue -u "$USER" -o "%.10i %.16j %.9P %.8T %.10M %.16R" 2>&1 | grep -E "a02_|JOBID"
echo "  a02 running=$(squeue -u "$USER" -h -t R -o '%j' | grep -c '^a02_')  pending=$(squeue -u "$USER" -h -t PD -o '%j' | grep -c '^a02_')"

echo "=== E FREE GPU SLOTS RIGHT NOW ==="
sinfo -p hgpu2p,hgpu2,hgpu4,hgpu8 -N -h -O "NodeHost:9,Partition:8,StateLong:9,Gres:9,GresUsed:14" 2>&1 | head -18

echo "=== F ADV531 PROGRESS (when will those 5 GPUs free up?) ==="
squeue -u "$USER" -h -t R -O "JobID:9,Name:16,NodeList:9,TimeUsed:10,TimeLimit:11" 2>&1 | head -8
