#!/bin/bash
# Read-only probe for the pre-peak small-limit run. No submission, no writes outside echo.
set -o pipefail
echo "=== HOST ==="
hostname; date '+%Y-%m-%dT%H:%M:%S%z'
echo "=== REPO ==="
if [ -d "$HOME/neuralhydrology/.git" ]; then
  cd "$HOME/neuralhydrology" || exit 1
  git rev-parse --abbrev-ref HEAD 2>&1
  git log -1 --format='%H %ad %s' --date=iso 2>&1
  for f in src/adversarial/scripts/coherent_attack.py src/adversarial/model_wrapper.py src/adversarial/data_loader.py neuralhydrology/datasetzoo/camelsus.py neuralhydrology/datautils/utils.py; do
    if [ -f "$f" ]; then sha256sum "$f"; else echo "MISSING $f"; fi
  done
else
  echo "NO_REPO"
fi
echo "=== DATA ==="
for d in "$HOME/neuralhydrology/data/camels_us" "$HOME/neuralhydrology/data/CAMELS_US"; do
  if [ -d "$d" ]; then echo "DIR $d"; ls "$d" | head -12; fi
done
M="$HOME/neuralhydrology/data/camels_us/basin_dataset_public_v1p2/basin_mean_forcing/maurer"
if [ -d "$M" ]; then echo "MAURER_HUC_DIRS $(ls "$M" | wc -l)"; fi
echo "=== MODEL CANDIDATES ==="
ls -d "$HOME"/neuralhydrology/results/18_lstm_fair_531/lstm_cudalstm_maurer_s100_* 2>&1 | head -5
P=/data1/home/sunyiq/hydrol85935_revision_20261008_001
if [ -d "$P" ]; then
  ls "$P" | head -20
  find "$P" -maxdepth 5 -type d -name '*maurer_s100*' 2>/dev/null | head -10
fi
echo "=== ENV ==="
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null || source "$HOME/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final && python -c "import torch, numpy, pandas, xarray; print('torch', torch.__version__, 'numpy', numpy.__version__, 'pandas', pandas.__version__, 'xarray', xarray.__version__)" 2>&1 | tail -2
echo "=== GPU FREE ==="
for part in hgpu2p hgpu2 hgpu4 hgpu8; do sinfo -p "$part" -N -h -O nodelist:10,statecompact:8,gres:14,gresused:24 2>&1; done
echo "=== MY QUEUE ==="
squeue -u "$USER" -h -o '%i %P %T %R' 2>&1 | head -30
echo "=== FAIRSHARE ==="
sshare -U -P 2>&1 | tail -2
echo "=== DONE ==="
