#!/bin/bash
# Unpack jdl payload v3 and sbatch the Phase-0 gate suite in the HPC environment.
# Login node: unpack + sbatch only. Purpose: independent-environment check of the joint-learning
# framework (gates must pass HERE before any HPC learning-seed batch is submitted).
set -o pipefail
ROOT=~/kuwei_paired
SRC=~/hpc_mailbox/payload/kuwei-paired-recal/v3
JDL=$ROOT/jdl_gate
mkdir -p $JDL
echo "=== A. payload v3 ==="
cd $SRC && sha256sum -c bundle_manifest.sha256 2>&1 | head -3 || true
tar -xzf $SRC/laos_jdl_v3.tar.gz -C $ROOT/laos && echo "unpacked v3" || echo "FAILED"
ls $ROOT/laos/basins/namou_kuwei/dl/highflow_2026_06_17/scripts/ | grep -E 'kuwei_joint|torch_xaj' || true
echo "=== B. write gate slurm ==="
cat > $JDL/jdl_gates.slurm <<'SLURM'
#!/usr/bin/env bash
#SBATCH -J kuwei-jdl-gates
#SBATCH -p hcpu48,hcpu48y
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
export OMP_NUM_THREADS=1
ROOT=$HOME/kuwei_paired
export KUWEI_LAOS_ROOT=$ROOT/laos
export KUWEI_FSL_ROOT=$ROOT/fsl
SCR=$ROOT/laos/basins/namou_kuwei/dl/highflow_2026_06_17/scripts
echo "[$(date)] node=$(hostname)"
python -c "import torch,numpy,pandas;print('torch',torch.__version__,'numpy',numpy.__version__,'pandas',pandas.__version__)"
python -u -B $SCR/kuwei_joint_da_learning.py --gates
echo "[$(date)] gates exit=$?"
SLURM
echo "=== C. submit ==="
cd $JDL && sbatch jdl_gates.slurm 2>&1 | tee $JDL/gate_jobid.txt || echo "sbatch FAILED"
squeue -u ${USER} -n kuwei-jdl-gates -o "%.10i %.14j %.10P %.8T %R" 2>&1 | head -4 || true
echo "=== DONE ==="
