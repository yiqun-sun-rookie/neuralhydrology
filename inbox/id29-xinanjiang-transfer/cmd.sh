#!/bin/bash
set -eo pipefail
TASK_ROOT=/data1/home/sunyiq/id29_xinanjiang_transfer_20260907_v01
JOB_RAW=$(cat "$TASK_ROOT/pilot_job_id.txt")
JOB_ID=${JOB_RAW%%;*}
case "$JOB_ID" in ''|*[!0-9]*) exit 3;; esac
date -Is
sacct -j "$JOB_ID" --format=JobID,JobName%24,State,ExitCode,Elapsed,AllocCPUS,MaxRSS,NodeList -P
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY'
import pathlib,json,hashlib,xml.etree.ElementTree as ET
root=pathlib.Path('/data1/home/sunyiq/id29_xinanjiang_transfer_20260907_v01')
tests=root/'pilot-tests.xml'
if tests.exists():
    print('TEST_SUMMARY',ET.parse(tests).getroot().find('testsuite').attrib)
for basin in ['01144000','01435000']:
    folder=root/'pilot'/basin
    candidates=folder/'candidates.jsonl'
    if candidates.exists():
        lines=candidates.read_text().splitlines()
        print('CANDIDATES',basin,len(lines))
    else:
        print('CANDIDATES',basin,0)
    result=folder/'result.json'
    if result.exists():
        print('BASIN_RESULT',basin,result.read_text())
summary=root/'pilot/summary.json'
if summary.exists():
    print('PILOT_SUMMARY_SHA256',hashlib.sha256(summary.read_bytes()).hexdigest())
    print('PILOT_SUMMARY',summary.read_text())
else:
    print('PILOT_SUMMARY_NOT_PRESENT')
PY
for suffix in out err; do
  LOGFILE="$TASK_ROOT/logs/id29-xaj-technical_${JOB_ID}.${suffix}"
  if test -f "$LOGFILE"; then printf 'LOG_%s\n' "$suffix"; tail -n 15 "$LOGFILE"; fi
done
printf 'STATUS_COMPLETE\n'
