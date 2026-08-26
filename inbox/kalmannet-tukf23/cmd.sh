#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf23_20260826
echo "=== PAYLOAD VERIFY ==="
cd ~/hpc_mailbox || exit 1
EXPECTED=d46abd8a929e6b581b0d34d4a025c352e10df957e01ff064f200f3461d8a3712
ACTUAL=$(sha256sum payload/kalmannet-tukf23/tukf23_hpc_payload_v1.tar.gz | cut -d' ' -f1)
echo "expected=$EXPECTED"
echo "actual=$ACTUAL"
[ "$ACTUAL" = "$EXPECTED" ] || { echo "PAYLOAD_HASH_MISMATCH"; exit 1; }
echo "=== EXTRACT ==="
mkdir -p $ROOT/logs $ROOT/results
tar -xzf payload/kalmannet-tukf23/tukf23_hpc_payload_v1.tar.gz -C $ROOT && echo "extracted"
ls $ROOT/bundle/worktree/scripts/ 2>&1 | head -6
ls $ROOT/slurm/ 2>&1
echo "=== SUBMIT ANCHOR SMOKE ==="
out=$(sbatch $ROOT/slurm/tukf23_anchor.slurm 2>&1); echo "$out"
JID=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+' || true)
[ -n "$JID" ] || { echo "SUBMIT_FAILED"; exit 1; }
echo "anchor_job=$JID"
squeue -u $USER -h 2>&1 | head -5 || true
