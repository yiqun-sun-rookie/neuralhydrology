#!/bin/bash
# Step 1 of 3: anchor decomposition diagnostic on the cluster.
# The anchor gate is 0.0 on the Windows workstation and up to 3.60e-2 here; this job saves both
# the torch mirror series and the read-only authority series and compares each against the
# workstation's saved series, to determine WHICH side moved.
# Fresh landing. Login node does unpack + sbatch only; no computation here.
set -o pipefail
ROOT=$HOME/kuwei_jdl_seedbatch_20260831
SRC=$HOME/hpc_mailbox/payload/kuwei-jdl-seedbatch/v1
FSLSRC=$HOME/hpc_mailbox/payload/kuwei-paired-recal/v1
mkdir -p $ROOT/laos $ROOT/fsl $ROOT/out $ROOT/logs
echo "=== A. verify payload ==="
cd $SRC && sha256sum -c bundle_manifest.sha256 2>&1 | head -3 || true
echo "=== B. unpack ==="
tar -xzf $SRC/laos_jdl_seedbatch_v1.tar.gz -C $ROOT/laos && echo "laos unpacked" || echo "laos FAILED"
tar -xzf $FSLSRC/fsl_code.tar.gz -C $ROOT/fsl && echo "fsl unpacked" || echo "fsl FAILED"
ls $ROOT/laos/basins/namou_kuwei/dl/highflow_2026_06_17/scripts/ 2>&1 | head -6 || true
ls $ROOT/laos/basins/namou_kuwei/dl/highflow_2026_06_17/results/kuwei_jdl_anchor_decomposition_20260831/local/ 2>&1 | head -8 || true
echo "=== C. write slurm ==="
cat > $ROOT/anchor_decompose.slurm <<'SLURM'
#!/usr/bin/env bash
#SBATCH -J kuwei-jdl-anchor
#SBATCH -p hcpu48,hcpu48y
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=2
#SBATCH -t 01:00:00
#SBATCH -o logs/kuwei-jdl-anchor-%j.out
#SBATCH -e logs/kuwei-jdl-anchor-%j.err
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
REF=$ROOT/laos/basins/namou_kuwei/dl/highflow_2026_06_17/results/kuwei_jdl_anchor_decomposition_20260831/local
echo "[$(date)] node=$(hostname)"
python -c "import torch,numpy;print('torch',torch.__version__,'numpy',numpy.__version__)"
cd $SCR
python -u kuwei_jdl_anchor_decompose.py --out $ROOT/out/anchor_hpc --reference $REF
echo "[$(date)] done"
SLURM
echo "=== D. submit ==="
cd $ROOT && sbatch anchor_decompose.slurm 2>&1 | tee $ROOT/anchor_jobid.txt || echo "sbatch FAILED"
squeue -u ${USER} -n kuwei-jdl-anchor -o "%.10i %.18j %.14P %.8T %R" 2>&1 | head -4 || true
echo "=== DONE ==="
