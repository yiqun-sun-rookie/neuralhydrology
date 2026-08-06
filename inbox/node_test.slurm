#!/usr/bin/env bash
# 单节点 GPU 健康测试。由 cmd.sh 用 --nodelist 指定具体节点提交。
# 同时验证铁律 1(不写--mem) / 2(set -eo) / 3(MKL)。
#SBATCH -J nodetest
#SBATCH -p hgpu2p
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH -t 00:05:00
#SBATCH -o /data1/home/sunyiq/hpc_mailbox/outbox/nodetest_%j.out
#SBATCH -e /data1/home/sunyiq/hpc_mailbox/outbox/nodetest_%j.err

set -eo pipefail

echo "=== NODE: $(hostname) JOB: $SLURM_JOB_ID ==="
echo "=== GRES: ${CUDA_VISIBLE_DEVICES:-none} ==="

echo "--- nvidia-smi ---"
nvidia-smi --query-gpu=index,name,memory.total,driver_version --format=csv,noheader 2>&1 || echo "NVIDIA_SMI_FAILED rc=$?"

echo "--- conda ---"
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || \
source $HOME/miniconda3/etc/profile.d/conda.sh
conda activate nh_final || { echo "CONDA_ACTIVATE_FAILED"; exit 1; }
echo "conda OK: $(which python)"

export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1

echo "--- torch CUDA init ---"
python -u -c "
import sys, torch
print('torch', torch.__version__)
print('cuda_available', torch.cuda.is_available())
if not torch.cuda.is_available():
    print('VERDICT: CUDA_INIT_FAILED'); sys.exit(2)
print('device_count', torch.cuda.device_count())
print('device_name', torch.cuda.get_device_name(0))
import time
t0=time.time()
a = torch.randn(4000,4000, device='cuda')
b = torch.randn(4000,4000, device='cuda')
c = (a@b).sum().item()
torch.cuda.synchronize()
print('matmul_ok sum=%.4e elapsed=%.2fs' % (c, time.time()-t0))
print('mem_alloc_MB', round(torch.cuda.memory_allocated()/1e6,1))
print('VERDICT: NODE_HEALTHY')
" 2>&1
RC=$?

echo "=== EXIT: $RC on $(hostname) ==="
exit $RC
