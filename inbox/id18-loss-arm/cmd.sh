#!/bin/bash
# ID18 seq=2: read-only E04 environment and isolation probe. No sbatch.
set -eo pipefail

echo "=== TIME_AND_RUNNER ==="
date -Is
echo "runner delivered id18-loss-arm seq=2"

echo "=== QUEUE ==="
squeue -u "$USER" -o "%.10i %.18j %.10P %.9T %.11M %.6D %R" 2>&1 | head -30

echo "=== PARTITION ==="
sinfo -p hgpu2p -o "%.10P %.6a %.10l %.6D %.6t %N" 2>&1

echo "=== MAIN_REPO_READ_ONLY ==="
git -C /data1/home/sunyiq/neuralhydrology rev-parse --abbrev-ref HEAD 2>&1
git -C /data1/home/sunyiq/neuralhydrology status --short 2>&1 | wc -l

echo "=== ISOLATED_TARGET ==="
if [ -e /data1/home/sunyiq/id18_e04_20260809 ]; then
    echo "TARGET_EXISTS"
    find /data1/home/sunyiq/id18_e04_20260809 -maxdepth 2 -type f 2>&1 | head -30
else
    echo "TARGET_ABSENT"
fi

echo "=== DATA_COVERAGE ==="
DATA=/data1/home/sunyiq/neuralhydrology/data/camels_us
test -d "$DATA/basin_mean_forcing/daymet"
test -d "$DATA/usgs_streamflow"
find "$DATA/basin_mean_forcing/daymet" -type f -name '*_lump_cida_forcing_leap.txt' 2>/dev/null | wc -l
for basin in 01022500 11475560 14362250; do
    forcing=$(find "$DATA/basin_mean_forcing/daymet" -type f -name "${basin}_lump_cida_forcing_leap.txt" -print -quit)
    echo "$basin forcing=$forcing"
    tail -1 "$forcing"
done

echo "=== PYTHON_ENVIRONMENT ==="
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
python - <<'PY'
import cma
import numpy
import pandas
import torch
import xarray
print("python_dependencies=PASS")
print("cma_version=" + cma.__version__)
print("torch_version=" + torch.__version__)
print("cuda_available=" + str(torch.cuda.is_available()))
PY

echo "=== STORAGE ==="
df -h /data1 2>&1 | tail -2
echo "E04_READ_ONLY_PROBE_PASS"
