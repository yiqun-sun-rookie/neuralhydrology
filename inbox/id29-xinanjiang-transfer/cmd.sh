#!/bin/bash
# Read-only snapshot of this isolated receiver stage.
set -eo pipefail
TASK_ROOT=/data1/home/sunyiq/id29_xinanjiang_transfer_20260907_v01
JOB_RAW=$(cat "$TASK_ROOT/receiver_job_id.txt")
JOB_ID=${JOB_RAW%%;*}
case "$JOB_ID" in ''|*[!0-9]*) exit 3;; esac
date -Is
sacct -j "$JOB_ID" --format=JobID,JobName%24,State,ExitCode,Start,End,Elapsed,AllocCPUS,MaxRSS,NodeList -P
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY'
import hashlib,json,pathlib
root=pathlib.Path('/data1/home/sunyiq/id29_xinanjiang_transfer_20260907_v01')
stage=root/'receiver'
counts={'basin_directories':0,'finished_basins':0,'successful_basins':0,'successful_arms':0,'failed_arms':0,'not_run_arms':0}
evaluation=stage/'evaluation'
if evaluation.exists():
    for directory in sorted(evaluation.iterdir()):
        if not directory.is_dir(): continue
        counts['basin_directories']+=1
        result=directory/'result.json'
        if result.exists():
            try: value=json.loads(result.read_text())
            except json.JSONDecodeError: value=None
            if value is not None:
                counts['finished_basins']+=1
                counts['successful_basins']+=value.get('status')=='success'
        for path in directory.glob('*.json'):
            if path.name in ('context.json','result.json'): continue
            try: value=json.loads(path.read_text())
            except json.JSONDecodeError: continue
            state=value.get('status')
            if state in ('success','failed','not_run'):
                key={'success':'successful_arms','failed':'failed_arms','not_run':'not_run_arms'}[state]
                counts[key]+=1
print('RECEIVER_PROGRESS',json.dumps(counts,sort_keys=True))
for name in ['execution.json','summary.json']:
    path=stage/name
    print(name.upper(),path.read_text() if path.exists() else 'NOT_PRESENT')
    if path.exists(): print(name.upper()+'_SHA256',hashlib.sha256(path.read_bytes()).hexdigest())
print('FROZEN_TRANSFER_SHA256',hashlib.sha256((root/'development/frozen_transfer.json').read_bytes()).hexdigest())
PY
for suffix in out err; do
  LOGFILE="$TASK_ROOT/logs/id29-xaj-receive_${JOB_ID}.${suffix}"
  if test -f "$LOGFILE"; then printf 'LOG_%s\n' "$suffix"; tail -n 12 "$LOGFILE"; fi
done
printf 'RECEIVER_STATUS_COMPLETE\n'
