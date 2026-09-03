#!/bin/bash
# TUKF09-455: read back the ngu203 health probe. Read-only, submits nothing.
set -o pipefail
DIAG_ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_pmon_probe_diagnostics_20260902/node_health_ngu203
JID=$(cat "$DIAG_ROOT/job/job_id.txt" 2>/dev/null)
echo "NGU203_HEALTH_JOB_ID=$JID"
echo "=== JOB STATE ==="
sacct -j "$JID" -X --format=JobID%10,JobName%26,State%12,ExitCode%8,NodeList%9,Elapsed%10,Start%20,End%20 2>&1
squeue -j "$JID" -h -o "%T %R" 2>&1
echo "=== JOB STDOUT ==="
OUT="$DIAG_ROOT/logs/health-$JID.out"
if [ -f "$OUT" ]; then sha256sum "$OUT"; echo "--- begin ---"; cat "$OUT"; echo "--- end ---"; else echo "ABSENT $OUT"; fi
echo "=== JOB STDERR ==="
ERR="$DIAG_ROOT/logs/health-$JID.err"
if [ -f "$ERR" ]; then sha256sum "$ERR"; echo "--- begin ---"; cat "$ERR"; echo "--- end ---"; else echo "ABSENT $ERR"; fi
echo "=== PREPARATION JOB STILL UNTOUCHED ==="
squeue -j 218635 -h -o "218635 %T %R start=%S" 2>&1
sinfo -p hgpu8 -o "%.10P %.6a %.6D %.8t %.24N %.20C" 2>&1
echo "TUKF09_455_NGU203_HEALTH_READBACK"
