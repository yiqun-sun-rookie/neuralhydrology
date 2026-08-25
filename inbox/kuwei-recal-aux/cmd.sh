#!/bin/bash
# Unpack payload v2 (path-portable scripts) and sbatch the HPC determinism gate.
set -o pipefail
ROOT=~/kuwei_paired
SRC=~/hpc_mailbox/payload/kuwei-paired-recal/v2
GATE=$ROOT/gate
mkdir -p $GATE

echo "=== A. payload v2 ==="
cd $SRC && sha256sum -c bundle_manifest.sha256 2>&1 | head -3 || true
tar -xzf $SRC/laos_code_v2.tar.gz -C $ROOT/laos && echo "unpacked v2" || echo "FAILED"

echo "=== B. write gate slurm ==="
cat > $GATE/gate.slurm <<'SLURM'
#!/usr/bin/env bash
#SBATCH -J kuwei-gate
#SBATCH -p hcpu48
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=2
#SBATCH -t 02:00:00
#SBATCH -o %x-%j.out
#SBATCH -e %x-%j.err
set -eo pipefail
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
export OMP_NUM_THREADS=1
ROOT=$HOME/kuwei_paired
export KUWEI_LAOS_ROOT=$ROOT/laos
export KUWEI_FSL_ROOT=$ROOT/fsl
export PYTHONPATH=$ROOT/fsl:$PYTHONPATH
SCR=$ROOT/laos/basins/namou_kuwei/dl/highflow_2026_06_17/scripts
echo "[$(date)] node=$(hostname)"
python -c "import numpy,scipy,numba;print('numpy',numpy.__version__,'scipy',scipy.__version__,'numba',numba.__version__)"
echo "--- preflight (no formal calibration) ---"
python -u $SCR/paired_rain_recalibration.py --preflight 2>&1 | tail -40
echo "--- determinism gate: same arm+seed twice, must be bitwise identical ---"
python -u $SCR/deterministic_fsl_calibration_adapter.py --determinism-gate \
  --output-root $ROOT/gate/out --arm current_input --seed 20260824 --max-iter 1
echo "[$(date)] gate exit=$?"
SLURM
echo "written"

echo "=== C. submit ==="
cd $GATE && sbatch gate.slurm 2>&1 | tee $GATE/gate_jobid.txt || echo "sbatch FAILED"
squeue -u ${USER} -n kuwei-gate -o "%.10i %.12j %.8T %R" 2>&1 | head -4 || true
echo "=== DONE ==="
