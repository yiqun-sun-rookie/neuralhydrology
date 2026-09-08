#!/bin/bash
# Read-only snapshot of the isolated two-basin recovery job.
set -eo pipefail
RECOVERY=/data1/home/sunyiq/id29_xinanjiang_transfer_20260907_v01_recovery_01
JOB_RAW=$(cat "$RECOVERY/job_id.txt")
JOB_ID=${JOB_RAW%%;*}
case "$JOB_ID" in ''|*[!0-9]*) exit 3;; esac
date -Is
sacct -j "$JOB_ID" --format=JobID,JobName%24,State,ExitCode,Start,End,Elapsed,AllocCPUS,MaxRSS,NodeList -P
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY'
import hashlib,json,pathlib
recovery=pathlib.Path('/data1/home/sunyiq/id29_xinanjiang_transfer_20260907_v01_recovery_01')
original=pathlib.Path('/data1/home/sunyiq/id29_xinanjiang_transfer_20260907_v01')
for name in ['execution.json','receiver/summary.json','submission_receipt.json','approve_recovery.json']:
    path=recovery/name
    print(name.upper(),path.read_text() if path.exists() else 'NOT_PRESENT')
    if path.exists(): print(name.upper()+'_SHA256',hashlib.sha256(path.read_bytes()).hexdigest())
manifest=json.loads((recovery/'source_receiver_manifest.json').read_text())
changed=[]
for name,expected in manifest.items():
    path=original/name
    actual=hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None
    if actual!=expected: changed.append({'path':name,'expected':expected,'actual':actual})
print('ORIGINAL_RECEIVER_FILES',len(manifest))
print('ORIGINAL_RECEIVER_MISMATCHES',json.dumps(changed,sort_keys=True))
print('RECOVERY_DIRECTORY_COUNT',sum(p.is_dir() for p in (recovery/'receiver/evaluation').glob('*'))
PY
for suffix in out err; do
  LOGFILE="$RECOVERY/logs/id29-xaj-rec2_${JOB_ID}.${suffix}"
  if test -f "$LOGFILE"; then printf 'LOG_%s\n' "$suffix"; tail -n 20 "$LOGFILE"; fi
done
printf 'RECOVERY_STATUS_COMPLETE\n'
