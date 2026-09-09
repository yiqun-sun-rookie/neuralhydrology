#!/bin/bash
# TUKF09-455 v2r13: submit the single preparation job once the offline inputs are published.
set -eo pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r13_20260909
P="$ROOT/bundle/kalmannet"
S="$P/hpc/tukf09_455_basin_revision_a800_exclusive_v2r13/probe_gpu.slurm"
echo "TIME=$(date -Is)"
M="$ROOT/offline_inputs_v2r13/manifest.json"
if pgrep -f "download_runtime_inputs_login.sh" >/dev/null 2>&1; then echo DOWNLOAD_STILL_RUNNING; du -sh "$ROOT"/offline_inputs_v2r13* 2>/dev/null; exit 0; fi
test -f "$M" || { echo OFFLINE_INPUTS_MISSING; tail -c 600 "$ROOT/logs/offline-inputs-download.out" 2>&1; exit 11; }
echo OFFLINE_INPUTS_PUBLISHED
echo "MANIFEST_SHA256=$(sha256sum "$M"|cut -d\" \" -f1)"
python -X utf8 -c "import json;d=json.load(open(\"$M\"));f=d.get(\"files\",{});print(\"FILE_COUNT\",len(f));print(\"TOTAL_BYTES\",sum(int(r[\"size\"]) for r in f.values()))" 2>&1
echo "=== JOB CARD ==="
grep -E "^#SBATCH (-p|-N|-n|--cpus-per-task|--gres|-t)" "$S"
echo "EXCLUSIVE_DIRECTIVES=$(grep -c -- "--exclusive" "$S" || true)"
if [ -d "$ROOT/status/preparation_submission.lock" ]; then echo ALREADY_SUBMITTED; cat "$ROOT/status/preparation_job_id.txt" 2>/dev/null; exit 0; fi
mkdir "$ROOT/status/preparation_submission.lock" || { echo LOCK_RACE; exit 12; }
JID=$(sbatch --parsable "$S"); JID=${JID%%;*}
echo "$JID" > "$ROOT/status/preparation_job_id.txt"
echo "PREPARATION_JOB_ID=$JID"
sleep 30
squeue -j "$JID" -o "%.10i %.10T %.11M %.11l %.9N %.24R" 2>&1
sacct -j "$JID" -X --format=JobID%10,State%12,Elapsed%10,NodeList%9 2>&1
squeue -u $USER --start 2>&1 | grep -E "$JID|START" || true
echo TUKF09_455_V2R13_PREPARATION_SUBMITTED
