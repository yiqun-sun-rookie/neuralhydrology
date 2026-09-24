#!/bin/bash
set -eo pipefail
sequence=20
root=/data1/home/sunyiq/kalmannet_hamid_weights_20260923_v1
job_id=$(cat "$root/diagnostic_submission_claim_20260924_v3/job_id.txt")
[[ "$job_id" =~ ^[0-9]+$ ]]
date -u '+SNAPSHOT_UTC=%Y-%m-%dT%H:%M:%SZ'
printf 'DIAGNOSTIC_JOB_ID=%s\n' "$job_id"
squeue -r -h -j "$job_id" -o '%i|%j|%T|%M|%R' || true
sacct -X -j "$job_id" -n -P --format=JobID,JobName%30,State,ExitCode,Elapsed,NodeList
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY'
import json
from pathlib import Path
root=Path('/data1/home/sunyiq/kalmannet_hamid_weights_20260923_v1/diagnostic_20260924_v3')
for part in ('preflight_cpu/result.json','preflight_gpu/result.json','full_batch_observer_audit.json','HALT.json','runs/*/full_batch_observer_parity.json','runs/*/diagnostic_training_observation.json','runs/*/diagnostic_summary.json','runs/*/failure.json','runs/*/started.json'):
 for p in sorted(root.glob(part)):
  d=json.loads(p.read_text())
  if part.startswith('preflight_'):
   d={k:v for k,v in d.items() if k!='rows'}
   d['all_eight_update_comparisons_passed']=all(all(r[k] for k in ('loss_equal','parameters_equal','optimizer_equal','rng_equal')) for r in json.loads(p.read_text())['rows'])
  if p.name=='full_batch_observer_audit.json':
   d={k:v for k,v in d.items() if k!='rows'}
  if p.name=='started.json':d={k:v for k,v in d.items() if k!='data'}
  print('FILE='+str(p));print(json.dumps(d))
for p in root.glob('runs/*/events.jsonl'):
 lines=p.read_text().splitlines();print('EVENT_COUNT='+str(len(lines)))
 for line in lines[:2]+lines[-2:]:print(line)
for p in sorted((root/'logs').glob('*')):
 if p.is_file():
  print('LOG='+str(p))
  for line in p.read_text(errors='replace').splitlines()[-12:]:print(line[:1800])
PY
printf '\nOWN_JOB_INVENTORY\n'
squeue -u sunyiq -h -o '%i|%j|%T|%P|%R'
printf '\nREAD_ONLY_DIAGNOSTIC_STATUS_COMPLETE\n'
