#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf23_20260826
echo "=== INSTALL SEAL (LF hash) ==="
cd ~/hpc_mailbox || exit 1
EXPECTED=f17db80c4780df0ffab643cc9b1750c085a8feb1bd8cf6222fbdd4dab84851fc
ACTUAL=$(sha256sum payload/kalmannet-tukf23/checkpoint_seal.json | cut -d' ' -f1)
echo "actual=$ACTUAL"
[ "$ACTUAL" = "$EXPECTED" ] || { echo "SEAL_HASH_MISMATCH"; exit 1; }
cp -f payload/kalmannet-tukf23/checkpoint_seal.json $ROOT/results/checkpoint_seal.json && echo "seal installed"
grep -o '"seal_sha256": "[a-f0-9]*"' $ROOT/results/checkpoint_seal.json | head -1
echo "=== SUBMIT READOUT ARRAY ==="
out=$(sbatch --array=0-107 $ROOT/slurm/tukf23_readout.slurm 2>&1); echo "$out"
JID=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+' || true)
[ -n "$JID" ] || { echo "SUBMIT_FAILED"; exit 1; }
echo "readout_array=$JID"
