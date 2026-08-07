#!/bin/bash
# a02 seq=15 : final diagnosis of the cluster-wide GPU accounting leak,
# plus a real CUDA test on ngu009 (the only node with a free GPU slot).
export LC_ALL=C

echo "=== A EVERY JOB IN EVERY STATE, ALL USERS ==="
squeue -a -t all -O "JobID:9,UserName:10,Partition:8,StateCompact:5,NodeList:11,tres-per-node:11,TimeUsed:9" 2>&1 | head -25
echo "  total lines above (excluding header) = jobs known to the scheduler"

echo "=== B SUSPENDED / COMPLETING ANYWHERE? ==="
squeue -a -t S,CG,CF,ST -O "JobID:9,UserName:9,StateCompact:5,NodeList:10" 2>&1 | head -8

echo "=== C NODE-LEVEL GRES DETAIL (three representative nodes) ==="
for N in ngu101 ngu201 ngu009; do
  echo "--- $N ---"
  scontrol show node $N 2>&1 | tr ' ' '\n' | grep -E "^(NodeName|State|Gres=|GresUsed|AllocTRES|CfgTRES|Reason)" | sed 's/^/    /'
done

echo "=== D CUDA TEST ON ngu009 (has 1 free GPU slot) ==="
cat > /tmp/a02_009.slurm <<'EOF'
#!/usr/bin/env bash
#SBATCH -J a02_nodetest
#SBATCH -p hgpu2
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH --nodelist=ngu009
#SBATCH -t 00:10:00
#SBATCH -o /data1/home/sunyiq/nature_1st_a02/logs/nodetest-%j.out
#SBATCH -e /data1/home/sunyiq/nature_1st_a02/logs/nodetest-%j.err
set -eo pipefail
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
echo "host=$(hostname)"
nvidia-smi --query-gpu=index,name --format=csv,noheader
python -c "
import torch
print('cuda_available', torch.cuda.is_available())
print('device_count', torch.cuda.device_count())
assert torch.cuda.is_available()
x = torch.randn(4000,4000,device='cuda'); print('matmul_ok', abs((x@x).sum().item())>0)
"
echo "NODE_TEST_PASS"
EOF
sed -i 's/\r$//' /tmp/a02_009.slurm
JID=$(sbatch --parsable /tmp/a02_009.slurm 2>&1)
echo "  jobid=$JID"
for i in $(seq 1 24); do
  ST=$(squeue -j "$JID" -h -o "%t" 2>/dev/null)
  [ -z "$ST" ] && { echo "  finished at t=$((i*10))s"; break; }
  sleep 10
done
sacct -j "$JID" -X --format=JobID%9,NodeList%9,State%11,ExitCode%7,Elapsed%9 2>&1
echo "--- output ---"
cat /data1/home/$USER/nature_1st_a02/logs/nodetest-${JID}.out 2>&1 | head -10
echo "--- stderr ---"
tail -4 /data1/home/$USER/nature_1st_a02/logs/nodetest-${JID}.err 2>&1

echo "=== E A02 STATUS ==="
echo "  running=$(squeue -u "$USER" -h -t R -o '%j' | grep -c '^a02_')  pending=$(squeue -u "$USER" -h -t PD -o '%j' | grep -c '^a02_')"
