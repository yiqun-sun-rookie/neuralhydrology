#!/bin/bash
# attrswap-daily seq=1 -- READ-ONLY recon for the daily-scale China-available attribute swap (7 arms).
# Nothing here writes, submits, or changes any git state.
set -o pipefail
date "+wallclock %F %T %z"; hostname
echo "=== A. CODE: is baseline commit 1f9804e in ~/neuralhydrology (read-only) ==="
cd /data1/home/sunyiq/neuralhydrology 2>/dev/null || echo "REPO_MISSING"
git cat-file -t 1f9804e359283f1963bcf0aa9ffab213538c16e8 2>&1 || true
echo "HEAD=$(git rev-parse --short HEAD 2>&1) branch=$(git rev-parse --abbrev-ref HEAD 2>&1)"
git show -s --format='%ci %s' 1f9804e359283f1963bcf0aa9ffab213538c16e8 2>&1 | head -1 || true
echo "=== B. DATA: ~/neuralhydrology/data/camels_us ==="
D=/data1/home/sunyiq/neuralhydrology/data/camels_us
ls -la "$D" 2>&1 | head -20
echo "--- basin_mean_forcing ---"; ls "$D/basin_mean_forcing" 2>&1
echo "maurer_files=$(find "$D/basin_mean_forcing/maurer" -type f 2>/dev/null | wc -l) streamflow_files=$(find "$D/usgs_streamflow" -type f 2>/dev/null | wc -l)"
echo "--- attributes ---"; ls -la "$D/camels_attributes_v2.0" 2>&1 | head -20
echo "=== C. DATA HASHES (per-dir combined sha256 prefix; compare with local) ==="
cd "$D" 2>/dev/null && for sub in basin_mean_forcing/maurer/* usgs_streamflow/* camels_attributes_v2.0; do
  [ -d "$sub" ] || continue
  h=$(find "$sub" -type f 2>/dev/null | LC_ALL=C sort | xargs sha256sum 2>/dev/null | sha256sum | cut -c1-16)
  echo "$sub $(find "$sub" -type f 2>/dev/null | wc -l) $h"
done
echo "--- one sample file: line endings + first header line ---"
f=$(find basin_mean_forcing/maurer -type f 2>/dev/null | LC_ALL=C sort | head -1); echo "$f crlf_lines=$(grep -c $'\r' "$f" 2>/dev/null || true)"; sed -n '4p' "$f" 2>/dev/null | cut -c1-160
echo "=== D. ENV nh_final packages ==="
ls /data1/home/sunyiq/miniconda3/envs/nh_final/lib/python3.11/site-packages 2>/dev/null | grep -iE "^(torch|numpy|pandas|xarray|scipy|ruamel|tqdm|numba|netcdf4|h5py|matplotlib)[-_.]" | head -24 || true
echo "=== E. SLURM ==="
sinfo -o "%.10P %.6a %.6D %.6t %.30N" 2>&1 | grep -E "PARTITION|hgpu" || true
echo "my_jobs=$(squeue -u $USER -h 2>/dev/null | wc -l)"
squeue -u $USER -h -o '%.11i %.30j %.9T %.10M %.9N %.9P' 2>&1 | head -20
echo "=== F. LANDING DIR (must not exist yet) ==="
ls -ld /data1/home/sunyiq/attr_swap_daily_2026_09 2>&1 || true
df -h /data1 2>&1 | tail -1
echo "=== DONE ==="
