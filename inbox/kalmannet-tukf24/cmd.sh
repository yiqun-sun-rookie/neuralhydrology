#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf24_20260827
echo "=== INSTALL SEAL ==="
cp -f payload/kalmannet-tukf24/tukf24_checkpoint_seal.json $ROOT/results/checkpoint_seal.json
sha256sum $ROOT/results/checkpoint_seal.json
echo "expect d91ff31be732b3c19d7f5dd175cddbff40624f79524033b06a828f9a46216127"
S=$(sha256sum $ROOT/results/checkpoint_seal.json | cut -d' ' -f1)
[ "$S" = "d91ff31be732b3c19d7f5dd175cddbff40624f79524033b06a828f9a46216127" ] || { echo SEAL_HASH_MISMATCH; exit 1; }
echo "=== SINGLE UNSEALING: SBATCH BOTH READOUT ARRAYS ==="
cd $ROOT
sbatch --array=0-107 $ROOT/slurm/tukf24_readout_new.slurm
sbatch --array=0-107 $ROOT/slurm/tukf24_readout_old.slurm
squeue -u $USER -p hcpu48y 2>/dev/null | head -8 || true
