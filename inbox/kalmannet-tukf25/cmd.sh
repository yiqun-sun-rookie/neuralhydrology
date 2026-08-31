#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf25_20260831
echo "=== INSTALL SEAL (verify bytes) ==="
EXPECT=2d83786e3a231d3d9dd35b1b96e781227a5fd7f77533afc5e9890afe8d438c31
ACTUAL=$(sha256sum payload/kalmannet-tukf25/checkpoint_seal.json | awk '{print $1}')
echo "expect=$EXPECT"
echo "actual=$ACTUAL"
[ "$ACTUAL" = "$EXPECT" ] || { echo "SEAL_HASH_MISMATCH"; exit 1; }
if [ -f $ROOT/results/checkpoint_seal.json ]; then
  echo "SEAL_ALREADY_INSTALLED (single-unseal discipline: not overwriting)"
else
  cp payload/kalmannet-tukf25/checkpoint_seal.json $ROOT/results/checkpoint_seal.json
  echo "seal installed"
fi
echo "=== SBATCH READOUT ARRAY 108 (single unsealing) ==="
if squeue -u $USER -h -o "%j" 2>/dev/null | grep -q tukf25_readout; then
  echo "READOUT_ALREADY_QUEUED (not resubmitting)"
else
  out=$(sbatch $ROOT/slurm/tukf25_readout.slurm 2>&1); echo "$out"
  echo "$out" | grep -qE 'Submitted batch job [0-9]+' || { echo "SUBMIT_FAILED"; exit 1; }
fi
echo "SEQ8_OK"
