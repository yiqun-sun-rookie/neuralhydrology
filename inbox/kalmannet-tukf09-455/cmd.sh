#!/bin/bash
# TUKF09-455 v2r13: read the preparation failure. Read only.
set -o pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r13_20260909
JID=$(cat "$ROOT/status/preparation_job_id.txt" 2>/dev/null)
echo "TIME=$(date -Is)  JOB=$JID"
sacct -j "$JID" --format=JobID%16,State%12,ExitCode%8,Elapsed%10,NodeList%9,MaxRSS%10 2>&1
echo "=== WHAT NODE WAS IT AND WHAT CARDS ==="
sinfo -p hgpu4 -N -O "NodeHost:12,StateLong:12,Gres:14,GresUsed:20,CPUsState:14" 2>&1
echo "=== prepare stderr (tail) ==="
tail -c 4000 "$ROOT/logs/prepare-$JID.err" 2>&1
echo "=== prepare stdout (tail) ==="
tail -c 2500 "$ROOT/logs/prepare-$JID.out" 2>&1
echo "=== status tree ==="
ls -la "$ROOT/status" 2>&1
echo TUKF09_455_V2R13_PREPARATION_FAILURE_EVIDENCE
