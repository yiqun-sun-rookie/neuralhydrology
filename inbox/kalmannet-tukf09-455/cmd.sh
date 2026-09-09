#!/bin/bash
# TUKF09-455 v2r13: wait for the offline inputs, then submit the single preparation job.
set -eo pipefail
ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r13_20260909
S="$ROOT/bundle/kalmannet/hpc/tukf09_455_basin_revision_a800_exclusive_v2r13/probe_gpu.slurm"
M="$ROOT/offline_inputs_v2r13/manifest.json"
echo "TIME=$(date -Is)"
for t in $(seq 1 45); do [ -f "$M" ] && break; pgrep -f download_runtime_inputs_login.sh >/dev/null 2>&1 || break; sleep 10; done
if [ ! -f "$M" ]; then echo NOT_PUBLISHED; du -sb /tmp/pip-unpack-* 2>/dev/null | awk "{s+=\$1} END {print \"pip_tmp_bytes\", s+0}"; pgrep -f "pip download" >/dev/null && echo PIP_STILL_RUNNING || { echo PIP_GONE; tail -c 900 "$ROOT/logs/offline-inputs-download.out"; }; exit 0; fi
echo OFFLINE_INPUTS_PUBLISHED
echo "MANIFEST_SHA256=$(sha256sum "$M"|cut -d\" \" -f1)"
python -X utf8 -c "import json;d=json.load(open(\"$M\"));f=d.get(\"files\",{});print(\"FILE_COUNT\",len(f));print(\"TOTAL_BYTES\",sum(int(r[\"size\"]) for r in f.values()))" 2>&1
grep -E "^#SBATCH (-p|--cpus-per-task|--gres|-t)" "$S"
if [ -d "$ROOT/status/preparation_submission.lock" ]; then echo ALREADY_SUBMITTED; cat "$ROOT/status/preparation_job_id.txt"; exit 0; fi
mkdir "$ROOT/status/preparation_submission.lock"
JID=$(sbatch --parsable "$S"); JID=${JID%%;*}
echo "$JID" > "$ROOT/status/preparation_job_id.txt"
echo "PREPARATION_JOB_ID=$JID"
sleep 30
squeue -j "$JID" -o "%.10i %.10T %.11M %.9N %.26R" 2>&1
echo TUKF09_455_V2R13_WAIT_AND_SUBMIT
