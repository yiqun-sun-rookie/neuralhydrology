#!/bin/bash
# kuwei paired rainfall recalibration -- reconnaissance only, no computation here
set -o pipefail

echo "=== A. host / date ==="
hostname; date; echo "PWD=$(pwd)"

echo "=== B. outbound network (decides whether HPC can clone by itself) ==="
getent hosts github.com >/dev/null && echo DNS_OK || echo DNS_FAIL
timeout 25 ssh -o ConnectTimeout=15 -T git@github.com 2>&1 | head -1 || true

echo "=== C. does any relevant repo already exist here? ==="
for d in ~/forecast_system_lite ~/laos_forecast ~/fsl ~/kuwei; do
  if [ -d "$d" ]; then echo "PRESENT $d"; else echo "absent  $d"; fi
done

echo "=== D. home quota / free space ==="
df -h ~ 2>/dev/null | tail -2 || true
quota -s 2>/dev/null | head -5 || echo "(no quota cmd)"

echo "=== E. conda env + the versions that decide determinism ==="
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null || \
source $HOME/miniconda3/etc/profile.d/conda.sh 2>/dev/null || \
source $HOME/anaconda3/etc/profile.d/conda.sh 2>/dev/null || echo "(conda.sh not found)"
conda env list 2>/dev/null | head -10 || true
conda activate nh_final 2>/dev/null && {
  python -c "import sys,numpy,scipy,pandas;print('python',sys.version.split()[0]);print('numpy ',numpy.__version__);print('scipy ',scipy.__version__);print('pandas',pandas.__version__)" 2>&1 || true
  python -c "import numba;print('numba ',numba.__version__)" 2>&1 || echo "numba MISSING"
  python -c "import yaml;print('pyyaml OK')" 2>&1 || echo "pyyaml MISSING"
} || echo "(nh_final activate failed)"

echo "=== F. CPU partitions (this job is pure single-thread CPU, no GPU needed) ==="
sinfo -o "%20P %10a %10l %6D %10t %N" 2>&1 | head -20 || true

echo "=== G. my running/queued jobs ==="
squeue -u ${USER} -o "%.10i %.14j %.10P %.8T %.10M %R" 2>&1 | head -15 || true

echo "=== DONE ==="
