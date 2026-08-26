#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf23_20260826
echo "=== VERIFY V2 PAYLOAD ==="
cd ~/hpc_mailbox || exit 1
EXPECTED=66b950660dd865134273a43ed86810cb9bbe559cadd2b760df0bf51686cdb080
ACTUAL=$(sha256sum payload/kalmannet-tukf23/tukf23_hpc_payload_v2.tar.gz | cut -d' ' -f1)
echo "actual=$ACTUAL"
[ "$ACTUAL" = "$EXPECTED" ] || { echo "PAYLOAD_HASH_MISMATCH"; exit 1; }
echo "=== CLEAN REDEPLOY ==="
mv $ROOT/results $ROOT/results_failed_attempt1 2>/dev/null || true
mv $ROOT/logs $ROOT/logs_failed_attempt1 2>/dev/null || true
rm -rf $ROOT/bundle $ROOT/slurm
mkdir -p $ROOT/logs $ROOT/results
tar -xzf payload/kalmannet-tukf23/tukf23_hpc_payload_v2.tar.gz -C $ROOT && echo "extracted v2"
ls $ROOT/bundle/kalmannet/scripts/ 2>&1
echo "=== SUBMIT ANCHOR GATE (v2) ==="
out=$(sbatch $ROOT/slurm/tukf23_anchor.slurm 2>&1); echo "$out"
JID=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+' || true)
[ -n "$JID" ] || { echo "SUBMIT_FAILED"; exit 1; }
echo "anchor_job_v2=$JID"
