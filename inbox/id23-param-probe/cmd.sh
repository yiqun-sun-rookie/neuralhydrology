#!/bin/bash
# Env check for the parameter-axis open-loop probe. Read-only, no sbatch.
echo "=== CONDA ENV (activate NOT piped this time) ==="
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh 2>/dev/null || source $HOME/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda activate nh_final
echo "which python: $(which python)"
python - <<'PY' 2>&1 | head -20
import sys
print("python", sys.version.split()[0])
for mod in ("numpy", "pandas", "numba", "pytest"):
    try:
        m = __import__(mod)
        print(f"{mod} {getattr(m, '__version__', '?')}")
    except Exception as exc:
        print(f"{mod} MISSING ({type(exc).__name__})")
PY

echo "=== CPU PARTITION HEADROOM ==="
sinfo -p hcpu48,hcpu48y -o "%.10P %.6t %.6D %N" 2>&1 | head -12

echo "=== DATA SPOT CHECK (read-only) ==="
ls ~/neuralhydrology/data/camels_us/basin_mean_forcing/ 2>&1 | head -6
ls ~/neuralhydrology/data/camels_us/basin_mean_forcing/maurer/ 2>&1 | head -4
find ~/neuralhydrology/data/camels_us/usgs_streamflow -name "08190500_streamflow_qc.txt" 2>/dev/null | head -2

echo "=== MY LANDING DIR ==="
ls -ld ~/id23_param_probe 2>&1 | head -2
