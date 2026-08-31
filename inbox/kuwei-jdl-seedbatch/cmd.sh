#!/bin/bash
# Step 2 of 3: stage-1 learning-seed stability batch, 16 single-core tasks.
# Criterion registered BEFORE this runs: docs/experiments/kuwei_jdl_seedbatch_20260831/
# PREREGISTRATION.md, sha256 462e8452e6e57774d843f2bc27d9f9d04b8d7b8db54d88cd7fbc461b7b4b4b8b
# Fixed start replicate 20260826 (smallest measured cross-machine drift, 6.08e-4 m3/s).
# Login node writes the array script and submits; no computation here.
set -o pipefail
ROOT=$HOME/kuwei_jdl_seedbatch_20260831
mkdir -p $ROOT/logs
echo "=== A. landing check ==="
ls $ROOT/laos/basins/namou_kuwei/dl/highflow_2026_06_17/scripts/kuwei_joint_da_learning.py 2>&1 || true
ls -d $ROOT/fsl/src/kernels/semi_distributed/core 2>&1 || true
echo "=== B. write array slurm ==="
cat > $ROOT/seedbatch_stage1.slurm <<'SLURM'
#!/usr/bin/env bash
#SBATCH -J kuwei-jdl-s1
#SBATCH -p hcpu48,hcpu48y
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=1
#SBATCH -a 0-15
#SBATCH -t 08:00:00
#SBATCH -o logs/kuwei-jdl-s1-%A_%a.out
#SBATCH -e logs/kuwei-jdl-s1-%A_%a.err
set -eo pipefail
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
export OMP_NUM_THREADS=1
ROOT=$HOME/kuwei_jdl_seedbatch_20260831
export KUWEI_LAOS_ROOT=$ROOT/laos
export KUWEI_FSL_ROOT=$ROOT/fsl
SCR=$ROOT/laos/basins/namou_kuwei/dl/highflow_2026_06_17/scripts
I=${SLURM_ARRAY_TASK_ID}
if   [ $I -eq 0 ];  then ARM=all_frozen; LS=0
elif [ $I -le 5 ];  then ARM=hydro_only; LS=$(( I - 1 ))
elif [ $I -le 10 ]; then ARM=joint;      LS=$(( I - 6 ))
else                     ARM=noise_only; LS=$(( I - 11 ))
fi
echo "[$(date)] task=$I arm=$ARM learning_seed=$LS node=$(hostname)"
python -c "import torch,numpy;print('torch',torch.__version__,'numpy',numpy.__version__)"
cd $SCR
python -u kuwei_joint_da_learning.py --run $ARM 20260826 --learning-seed $LS
echo "[$(date)] task=$I done"
SLURM
echo "=== C. submit ==="
cd $ROOT && sbatch seedbatch_stage1.slurm 2>&1 | tee $ROOT/stage1_jobid.txt || echo "sbatch FAILED"
squeue -u ${USER} -n kuwei-jdl-s1 -o "%.14i %.14j %.14P %.10T %R" 2>&1 | head -6 || true
echo "=== DONE ==="
