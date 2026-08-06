#!/bin/bash
# seq=12 : preflight for nature_1st S01 seed-ensemble experiment (read-only)

echo "=== A ENV nh_final ==="
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null || \
source $HOME/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda activate nh_final 2>&1 | head -2
python -c "
import sys
print('python', sys.version.split()[0])
for m in ['torch','pandas','numpy','pyarrow','tqdm','sklearn','scipy']:
    try:
        mod=__import__(m)
        print('  OK  ', m, getattr(mod,'__version__','?'))
    except Exception as e:
        print('  MISS', m, type(e).__name__)
import torch
print('cuda_built', torch.version.cuda)
" 2>&1 | head -20

echo "=== B HOME LAYOUT ==="
ls -d ~/nature_1st* ~/hpc_mailbox ~/neuralhydrology 2>&1 | head -8
echo "--- space ---"
df -h /data1 2>&1 | tail -2

echo "=== C GPU PARTITIONS ==="
sinfo -p hgpu2p,hgpu4,hgpu2 -o "%12P %6a %8D %20N %8t" 2>&1 | head -12

echo "=== D MY JOBS ==="
squeue -u "$USER" 2>&1 | head -6

echo "=== E SFTP LANDING DIR ==="
ls -la ~/ 2>&1 | head -12
