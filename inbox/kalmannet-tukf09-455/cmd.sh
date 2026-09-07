#!/bin/bash
# TUKF09-455: read the finished shared-node probe (job 223628). Read only.
set -o pipefail
PROBE=/data1/home/sunyiq/tukf09_455_shared_node_probe_20260907
JID=$(cat "$PROBE/job_id.txt" 2>/dev/null); JID=${JID%%;*}
echo "TIME=$(date -Is)  PROBE_JOB_ID=$JID"
sacct -j "$JID" -X --format=JobID%10,State%12,ExitCode%8,Elapsed%10,NodeList%9,Start%20,End%20 2>&1
echo "=== probe stdout ==="; cat "$PROBE"/probe-*.out 2>&1
echo "=== probe stderr ==="; cat "$PROBE"/probe-*.err 2>&1 | tail -20
echo TUKF09_455_SHARED_NODE_PROBE_READ
