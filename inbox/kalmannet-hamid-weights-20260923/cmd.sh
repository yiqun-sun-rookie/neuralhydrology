#!/bin/bash
set -eo pipefail
sequence=23
root=/data1/home/sunyiq/kalmannet_hamid_weights_20260923_v1
attempt="$root/diagnostic_20260924_v3"
job_id=$(cat "$root/diagnostic_submission_claim_20260924_v3/job_id.txt")
[[ "$job_id" =~ ^[0-9]+$ ]]
date -u '+SNAPSHOT_UTC=%Y-%m-%dT%H:%M:%SZ'
printf 'DIAGNOSTIC_JOB_ID=%s\n' "$job_id"
squeue -r -h -j "$job_id" -o '%i|%j|%T|%M|%R' || true
sacct -X -j "$job_id" -n -P --format=JobID,JobName%30,State,ExitCode,Elapsed,NodeList
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY'
import json,hashlib
from pathlib import Path
root=Path('/data1/home/sunyiq/kalmannet_hamid_weights_20260923_v1/diagnostic_20260924_v3')
for p in sorted(root.glob('runs/*')):
 if not p.is_dir():continue
 print('RUN_DIR='+str(p))
 for name in ('full_batch_observer_parity.json','diagnostic_training_observation.json','diagnostic_summary.json','failure.json'):
  f=p/name
  if f.is_file():
   d=json.loads(f.read_text());print('FILE='+str(f));
   if name=='diagnostic_summary.json':
    d={k:v for k,v in d.items() if k!='probes'}
   print(json.dumps(d)[:16000])
 events=p/'events.jsonl'
 if events.is_file():
  rows=[json.loads(x) for x in events.read_text().splitlines() if x.strip()]
  kinds={name:sum(x.get('event')==name for x in rows) for name in ('training_batch','epoch_complete','FIRST_OPTIMIZER_UPDATE_VERIFIED')}
  print('EVENT_COUNTS='+json.dumps(kinds))
  for row in rows[-5:]:print('LAST_EVENT='+json.dumps(row)[:2000])
 for f in sorted(p.glob('replay_*/result.json')):
  d=json.loads(f.read_text())
  print('PROBE='+json.dumps({k:d.get(k) for k in ('mode','state','preclip_gradient_norm','loss','model_unchanged','optimizer_unchanged','optimizer_update_performed')})[:3000])
for name in ('HALT.json','full_batch_observer_audit.json'):
 p=root/name
 if p.is_file():
  d=json.loads(p.read_text())
  if name=='full_batch_observer_audit.json':d={k:v for k,v in d.items() if k!='rows'}
  print('FILE='+str(p));print(json.dumps(d)[:5000])
for p in sorted((root/'logs').glob('*')):
 if p.is_file():
  print('LOG='+str(p))
  for line in p.read_text(errors='replace').splitlines()[-18:]:print(line[:1500])
PY
printf '\nOWN_JOB_INVENTORY\n'
squeue -u sunyiq -h -o '%i|%j|%T|%P|%R'
printf '\nREAD_ONLY_DIAGNOSTIC_STATUS_COMPLETE\n'
