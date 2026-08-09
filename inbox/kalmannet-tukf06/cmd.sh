#!/bin/bash
set -eo pipefail

echo "=== HCPU48 AVAILABILITY ==="
sinfo -p hcpu48 -N -o "%12N %12P %10T %5c %10m %10e %30E" 2>&1 | head -90

echo "=== HCPU48 PARTITION POLICY ==="
scontrol show partition hcpu48 2>&1 | head -50

echo "=== CURRENT USER CPU JOBS ==="
squeue -u "$USER" -p hcpu48 -o "%.18i %.24j %.10P %.8T %.10M %.20R" 2>&1 | head -50

echo "=== DATA FILE EXAMPLES ==="
find /data1/home/sunyiq/neuralhydrology/data/camels_us/basin_mean_forcing/maurer \
  -maxdepth 2 -type f -name '04105700*' -print 2>/dev/null | head -5
find /data1/home/sunyiq/neuralhydrology/data/camels_us/usgs_streamflow \
  -maxdepth 2 -type f -name '04105700*' -print 2>/dev/null | head -5

echo "=== STANDALONE DATA LOADER ==="
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || source "$HOME/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final
python - <<'PY'
import importlib.util
from pathlib import Path
path = Path('/data1/home/sunyiq/neuralhydrology/src/hydroagent/data_loading.py')
spec = importlib.util.spec_from_file_location('tukf06_data_loading', path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
print('LOADER_FILE', path)
print('LOAD_CAMELS_BASIN_AVAILABLE', callable(module.load_camels_basin))
PY
