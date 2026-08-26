#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf23_20260826
echo "=== INSTALL SEAL ==="
cd ~/hpc_mailbox || exit 1
ACTUAL=$(sha256sum payload/kalmannet-tukf23/checkpoint_seal.json | cut -d' ' -f1)
echo "actual=$ACTUAL"
[ "$ACTUAL" = "491a85123b3a54820d3f3bb1ee54cba71d71ab13a1bb0cc8a1e63d0402e71295" ] || { echo "SEAL_HASH_MISMATCH"; exit 1; }
cp -f payload/kalmannet-tukf23/checkpoint_seal.json $ROOT/results/checkpoint_seal.json && echo "seal installed"
echo "=== SUBMIT READOUT ARRAY (108 cells, test segment unsealing) ==="
out=$(sbatch --array=0-107 $ROOT/slurm/tukf23_readout.slurm 2>&1); echo "$out"
JID=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+' || true)
[ -n "$JID" ] || { echo "SUBMIT_FAILED"; exit 1; }
echo "readout_array=$JID"
