#!/bin/bash
set -eo pipefail
sequence=25
root=/data1/home/sunyiq/kalmannet_hamid_weights_20260923_v1
attempt="$root/finite_step_20260924_v1"
job_id=$(cat "$root/finite_step_submission_claim_20260924_v1/job_id.txt")
[[ "$job_id" =~ ^[0-9]+$ ]]
date -u '+SNAPSHOT_UTC=%Y-%m-%dT%H:%M:%SZ'
printf 'ONE_STEP_JOB_ID=%s\n' "$job_id"
squeue -r -h -j "$job_id" -o '%i|%j|%T|%M|%R' || true
sacct -X -j "$job_id" -n -P --format=JobID,JobName%30,State,ExitCode,Elapsed,NodeList
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY'
import json
from pathlib import Path
root=Path('/data1/home/sunyiq/kalmannet_hamid_weights_20260923_v1/finite_step_20260924_v1')
for name in ('deployment.json','pre_update.json','result.json','failure.json'):
 p=root/name
 if p.is_file():
  d=json.loads(p.read_text())
  if name=='result.json':
   updates=d.pop('actual_parameter_updates',{})
   d['parameter_tensors_with_update']=len(updates)
   d['max_absolute_parameter_update']=max((v['max_abs'] for v in updates.values()),default=0)
  print('FILE='+str(p));print(json.dumps(d)[:15000])
for p in sorted((root/'logs').glob('*')):
 if p.is_file():
  print('LOG='+str(p))
  for line in p.read_text(errors='replace').splitlines()[-15:]:print(line[:2000])
PY
printf '\nOWN_JOB_INVENTORY\n'
squeue -u sunyiq -h -o '%i|%j|%T|%P|%R'
printf '\nREAD_ONLY_ONE_STEP_STATUS_COMPLETE\n'
