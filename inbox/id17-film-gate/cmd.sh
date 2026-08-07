#!/bin/bash
# ID17 FiLM gate: read-only reconnaissance before any sbatch
echo "=== A. RUNNING JOBS (must not disturb) ==="
squeue -u "$USER" -o "%.10i %.14j %.9P %.8T %.10M %.6D %R" 2>&1

echo "=== B. PARTITION hgpu2p ==="
sinfo -p hgpu2p -o "%.10P %.6a %.10l %.6D %.6t %N" 2>&1 | head -8

echo "=== C. REPO STATE ==="
cd ~/neuralhydrology 2>/dev/null && { git rev-parse --abbrev-ref HEAD; git log --oneline -1; echo "dirty files: $(git status --porcelain 2>/dev/null | wc -l)"; } || echo "NO REPO"

echo "=== D. CAMELS_US DATA ==="
ls -d ~/neuralhydrology/data/*CAMELS* ~/neuralhydrology/data/*camels* 2>/dev/null
for d in ~/neuralhydrology/data/CAMELS_US ~/neuralhydrology/data/camels_us; do
  [ -d "$d" ] && { echo "--- $d ---"; ls "$d" 2>&1 | head -8; }
done

echo "=== E. FORCING + ATTRIBUTES ==="
find ~/neuralhydrology/data -maxdepth 3 -type d \( -name "basin_mean_forcing" -o -name "camels_attributes*" -o -name "usgs_streamflow" \) 2>/dev/null | head -6

echo "=== F. FOLD BASIN FILES (static_falsification) ==="
ls ~/neuralhydrology/src/static_falsification/data/fold*_*.txt 2>&1 | head -20
wc -l ~/neuralhydrology/src/static_falsification/data/fold0_train.txt 2>&1

echo "=== G. CONDA ENV ==="
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null || source $HOME/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda activate nh_final 2>&1 && python -c "import torch,sys; print('py',sys.version.split()[0],'torch',torch.__version__)" 2>&1

echo "=== H. DISK + HOME DIRS ==="
df -h /data1 2>&1 | tail -2
ls -d ~/id17* ~/v09_strict ~/nature_1st_a02 ~/adv531 2>/dev/null
