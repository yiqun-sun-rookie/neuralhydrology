#!/bin/bash
# a02 seq=13 : is ngu002 usable today? (it is the only node with free GPUs)
# 16 GPUs show as allocated cluster-wide but only 5 jobs are actually running,
# so 11 are ghost allocations. ngu002 is the only node reporting gpu:0 used.
export LC_ALL=C

echo "=== A CURRENT A02 QUEUE (any movement?) ==="
squeue -u "$USER" -h -o "%.10i %.16j %.8T %.10M %.18R" 2>&1 | grep "a02_" | head -14
echo "  running=$(squeue -u "$USER" -h -t R -o '%j' | grep -c '^a02_')  pending=$(squeue -u "$USER" -h -t PD -o '%j' | grep -c '^a02_')"

echo "=== B GRES USED RIGHT NOW ==="
sinfo -p hgpu2p -N -O "NodeHost:9,StateLong:8,GresUsed:16" 2>&1 | head -12

echo "=== C SUBMIT A 60-SECOND CUDA TEST PINNED TO ngu002 ==="
cat > /tmp/a02_ngu002_test.slurm <<'EOF'
#!/usr/bin/env bash
#SBATCH -J a02_nodetest
#SBATCH -p hgpu2p
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH --nodelist=ngu002
#SBATCH -t 00:10:00
#SBATCH -o /data1/home/sunyiq/nature_1st_a02/logs/nodetest-%j.out
#SBATCH -e /data1/home/sunyiq/nature_1st_a02/logs/nodetest-%j.err
set -eo pipefail
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
echo "host=$(hostname)"
nvidia-smi --query-gpu=index,name,memory.total --format=csv,noheader
python -c "
import torch
print('cuda_available', torch.cuda.is_available())
print('device_count', torch.cuda.device_count())
assert torch.cuda.is_available(), 'CUDA NOT AVAILABLE'
x = torch.randn(4000, 4000, device='cuda')
y = (x @ x).sum().item()
print('matmul_ok', abs(y) > 0)
"
echo "NODE_TEST_PASS"
EOF
sed -i 's/\r$//' /tmp/a02_ngu002_test.slurm
JID=$(sbatch --parsable /tmp/a02_ngu002_test.slurm 2>&1)
echo "  jobid=$JID"

echo "=== D WAIT (max 5 min) ==="
for i in $(seq 1 30); do
  ST=$(squeue -j "$JID" -h -o "%t" 2>/dev/null)
  [ -z "$ST" ] && { echo "  finished at t=$((i*10))s"; break; }
  [ $((i % 6)) -eq 0 ] && echo "  t=$((i*10))s state=$ST"
  sleep 10
done

echo "=== E VERDICT ==="
sacct -j "$JID" -X --format=JobID%9,NodeList%9,State%11,ExitCode%7,Elapsed%9 2>&1
echo "--- output ---"
cat /data1/home/$USER/nature_1st_a02/logs/nodetest-${JID}.out 2>&1 | head -12
echo "--- stderr ---"
tail -5 /data1/home/$USER/nature_1st_a02/logs/nodetest-${JID}.err 2>&1
