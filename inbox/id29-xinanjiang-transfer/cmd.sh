#!/bin/bash
set -eo pipefail
TASK_ROOT=/data1/home/sunyiq/id29_xinanjiang_transfer_20260907_v01
JOB_RAW=$(cat "$TASK_ROOT/development_job_id.txt")
JOB_ID=${JOB_RAW%%;*}
case "$JOB_ID" in ''|*[!0-9]*) exit 3;; esac
date -Is
sacct -j "$JOB_ID" --format=JobID,JobName%24,State,ExitCode,Elapsed,AllocCPUS,MaxRSS,NodeList -P
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY'
import json,pathlib
root=pathlib.Path('/data1/home/sunyiq/id29_xinanjiang_transfer_20260907_v01')
learning=root/'development/learning'
counts={}
if learning.exists():
    for path in sorted(learning.glob('*/candidates.jsonl')):
        with path.open() as stream:
            counts[path.parent.name]=sum(1 for line in stream if line.strip())
print('CANDIDATE_COUNTS',json.dumps(counts,sort_keys=True))
print('TOTAL_CANDIDATE_RECORDS',sum(counts.values()))
summary=root/'development/summary.json'
print('DEVELOPMENT_SUMMARY',summary.read_text() if summary.exists() else 'NOT_PRESENT')
print('RECEIVER_SUBMITTED',(root/'receiver_job_id.txt').exists())
PY
for suffix in out err; do
  LOGFILE="$TASK_ROOT/logs/id29-xaj-learn_${JOB_ID}.${suffix}"
  if test -f "$LOGFILE"; then printf 'LOG_%s\n' "$suffix"; tail -n 12 "$LOGFILE"; fi
done
printf 'STATUS_COMPLETE\n'
