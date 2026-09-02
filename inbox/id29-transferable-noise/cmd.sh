#!/bin/bash
# id29-transferable-noise seq=1: READ-ONLY environment survey.
# No compute, no writes anywhere. Only lists/queries.
set -o pipefail
echo "=== HOST/TIME ==="
hostname; date '+%F %T %z'
echo "=== MY JOBS (squeue -u, own jobs only) ==="
squeue -u "$USER" -o "%.9i %.12P %.26j %.3t %.10M %.5C %.12R" 2>&1 | head -40 || true
echo "=== PARTITION SUMMARY (sinfo) ==="
sinfo -o "%.10P %.6a %.6D %.6t %.30N" 2>&1 | head -30 || true
echo "=== hgpu2p PER-NODE CPU (alloc/idle/other/total) ==="
sinfo -p hgpu2p -N -o "%.10N %.6t %.5c %.22C %.8O" 2>&1 | head -20 || true
echo "=== CAMELS DATA CANDIDATES ==="
for d in /data1/home/sunyiq/neuralhydrology/data/camels_us; do
  if [ -d "$d" ]; then
    echo "DIR $d"; ls "$d" 2>&1 | head -20
    echo "-- basin_mean_forcing --"; ls "$d/basin_mean_forcing" 2>&1 | head -10
    echo "-- maurer sample --"; ls "$d/basin_mean_forcing/maurer" 2>&1 | head -3
    echo "-- maurer_extended sample --"; ls "$d/basin_mean_forcing/maurer_extended" 2>&1 | head -3
    echo "-- usgs_streamflow sample --"; ls "$d/usgs_streamflow" 2>&1 | head -3
    echo "-- attributes --"; ls "$d/camels_attributes_v2.0" 2>&1 | head -12
  else
    echo "MISSING $d"
  fi
done
echo "=== other camels_us dirs under home (maxdepth 3) ==="
find /data1/home/sunyiq -maxdepth 3 -type d -name camels_us 2>/dev/null | head -10 || true
echo "=== PYTHON ENV nh_final (import check only) ==="
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh 2>/dev/null || source "$HOME/miniconda3/etc/profile.d/conda.sh" 2>/dev/null
conda activate nh_final 2>&1 | tail -1 || true
python -c "import sys,numpy,pandas; print('python',sys.version.split()[0],'numpy',numpy.__version__,'pandas',pandas.__version__)" 2>&1 || true
python -c "import scipy; print('scipy',scipy.__version__)" 2>&1 || echo "scipy MISSING"
echo "=== DISK ==="
df -h /data1 2>&1 | tail -1 || true
echo "=== LANDING DIR (expect: not yet) ==="
ls -d /data1/home/sunyiq/id29_transferable_noise_20260902 2>&1 || true
echo "=== DONE ==="
