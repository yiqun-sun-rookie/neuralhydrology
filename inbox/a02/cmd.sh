#!/bin/bash
# a02 seq=14 : hgpu2p has no usable GPU (11 ghost allocs + ngu002 broken).
# Check the other GPU partitions and CUDA-test one node there.
export LC_ALL=C

echo "=== A ALL GPU PARTITIONS: GRES USED ==="
sinfo -p hgpu4,hgpu2,hgpu8 -N -O "NodeHost:9,Partition:9,StateLong:10,Gres:10,GresUsed:16,CPUsState:14" 2>&1 | head -16

echo "=== B RUNNING JOBS ON THOSE PARTITIONS (all users) ==="
squeue -p hgpu4,hgpu2,hgpu8 -t R -O "JobID:9,UserName:9,Partition:8,NodeList:10,tres-per-node:11,TimeUsed:9" 2>&1 | head -12
echo "  (empty means nothing running there)"

echo "=== C PICK A CANDIDATE AND CUDA-TEST IT ==="
CAND=$(sinfo -p hgpu4 -N -h -O "NodeHost:9,StateLong:10,GresUsed:16" 2>/dev/null | awk '$2=="idle" && $3 ~ /gpu:0/ {print $1; exit}')
[ -z "$CAND" ] && CAND=$(sinfo -p hgpu2 -N -h -O "NodeHost:9,StateLong:10,GresUsed:16" 2>/dev/null | awk '$2=="idle" && $3 ~ /gpu:0/ {print $1; exit}')
echo "  candidate node: ${CAND:-NONE FOUND}"

if [ -n "$CAND" ]; then
  PART=hgpu4
  case "$CAND" in ngu003|ngu009) PART=hgpu2 ;; esac
  cat > /tmp/a02_cand_test.slurm <<EOF
#!/usr/bin/env bash
#SBATCH -J a02_nodetest
#SBATCH -p $PART
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH --nodelist=$CAND
#SBATCH -t 00:10:00
#SBATCH -o /data1/home/sunyiq/nature_1st_a02/logs/nodetest-%j.out
#SBATCH -e /data1/home/sunyiq/nature_1st_a02/logs/nodetest-%j.err
set -eo pipefail
source /data1/home/\${USER}/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
echo "host=\$(hostname) partition=$PART"
nvidia-smi --query-gpu=index,name,memory.total --format=csv,noheader
python -c "
import torch
print('cuda_available', torch.cuda.is_available())
print('device_count', torch.cuda.device_count())
assert torch.cuda.is_available()
x = torch.randn(4000,4000,device='cuda'); print('matmul_ok', abs((x@x).sum().item())>0)
"
echo "NODE_TEST_PASS"
EOF
  sed -i 's/\r$//' /tmp/a02_cand_test.slurm
  JID=$(sbatch --parsable /tmp/a02_cand_test.slurm 2>&1)
  echo "  test jobid=$JID on $CAND ($PART)"
  for i in $(seq 1 30); do
    ST=$(squeue -j "$JID" -h -o "%t" 2>/dev/null)
    [ -z "$ST" ] && { echo "  finished at t=$((i*10))s"; break; }
    sleep 10
  done
  sacct -j "$JID" -X --format=JobID%9,NodeList%9,State%11,ExitCode%7,Elapsed%9 2>&1
  echo "--- output ---"
  cat /data1/home/$USER/nature_1st_a02/logs/nodetest-${JID}.out 2>&1 | head -10
fi

echo "=== D A02 QUEUE STILL STUCK? ==="
echo "  running=$(squeue -u "$USER" -h -t R -o '%j' | grep -c '^a02_')  pending=$(squeue -u "$USER" -h -t PD -o '%j' | grep -c '^a02_')"
