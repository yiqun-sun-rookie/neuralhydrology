#!/bin/bash
# Read-only probe for the Nearing 2022 DA/AR reproduction (ID29).
# Nothing here computes; all heavy work goes through sbatch later.

echo "=== A: repo ==="
if [ -d ~/neuralhydrology ]; then
  cd ~/neuralhydrology && git log --oneline -1 && echo "uncommitted: $(git status --porcelain | wc -l)" && cd ~
else
  echo "NO ~/neuralhydrology"
fi

echo "=== B: home layout ==="
ls ~ | head -30

echo "=== C: where is CAMELS ==="
find ~ -maxdepth 5 -type d -name "basin_mean_forcing" 2>/dev/null | head -5

echo "=== D: forcing products present ==="
for f in $(find ~ -maxdepth 5 -type d -name "basin_mean_forcing" 2>/dev/null | head -3); do
  echo "-- $f"
  ls "$f" 2>/dev/null
  du -sh "$f" 2>/dev/null | tail -1
done

echo "=== E: attributes + streamflow ==="
find ~ -maxdepth 5 -type d \( -name "camels_attributes_v2.0" -o -name "usgs_streamflow" \) 2>/dev/null | head -5

echo "=== F: conda env ==="
source ~/miniconda3/etc/profile.d/conda.sh 2>/dev/null || source ~/anaconda3/etc/profile.d/conda.sh 2>/dev/null
conda env list 2>&1 | head -10
conda run -n nh_final python -c "import torch,sys;print('py',sys.version.split()[0],'torch',torch.__version__,'cuda',torch.version.cuda)" 2>&1 | tail -3

echo "=== G: gpu partitions ==="
sinfo -o "%.12P %.6a %.11l %.5D %.6t %N" 2>&1 | head -15

echo "=== H: disk ==="
df -h /data1/home/sunyiq 2>&1 | tail -2
