#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf24_20260827
echo "=== INSTALL SEAL (corrected file-bytes hash) ==="
cp -f payload/kalmannet-tukf24/tukf24_checkpoint_seal.json $ROOT/results/checkpoint_seal.json
S=$(sha256sum $ROOT/results/checkpoint_seal.json | cut -d' ' -f1)
echo "file sha $S"
[ "$S" = "49f35e7d46995c4265f2efac76cda8c41930415236a927bd24af38890f881acf" ] || { echo SEAL_HASH_MISMATCH; exit 1; }
echo "=== SINGLE UNSEALING: SBATCH BOTH READOUT ARRAYS ==="
cd $ROOT
sbatch --array=0-107 $ROOT/slurm/tukf24_readout_new.slurm
sbatch --array=0-107 $ROOT/slurm/tukf24_readout_old.slurm
squeue -u $USER -p hcpu48y 2>/dev/null | head -8 || true
