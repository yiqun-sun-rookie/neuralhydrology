#!/usr/bin/env bash
set -eo pipefail
ROOT=/data1/home/sunyiq/hydrol85935_revision_20261008_001
test "$(readlink -f "$ROOT")" = "$ROOT"
test "$(cat "$ROOT/OWNER")" = hydrol85935_revision_20261008_001
date -Is
squeue -u "$USER" -o '%.18i %.14P %.35j %.10T %.12M %.8C %.20b %.30R'
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - <<'PY'
import json
from pathlib import Path
import subprocess
root=Path('/data1/home/sunyiq/hydrol85935_revision_20261008_001')
paths=[
 'control/continuation_v004/status.json',
 'control/continuation_v004/coordinator_pid',
 'control/preflight_v004_job_id',
 'control/preflight_v004_submission.txt',
 'preflight/v004/preflight/original_s100_01022500/report.json',
 'control/resource_pilot_v004_job_id',
 'control/resource_pilot_v004_submission.txt',
 'control/resource_pilot_v004.json',
 'control/full_v004/jobs.json',
 'control/continuation_v004/formal_submission.log',
]
for relative in paths:
 p=root/relative
 print('\nFILE '+relative,flush=True)
 if p.is_file():
  print(json.dumps({'bytes':p.stat().st_size,'mtime_ns':p.stat().st_mtime_ns}),flush=True)
  print(p.read_text()[-18000:],flush=True)
 else:print('NOT_CREATED',flush=True)
pid_path=root/'control/continuation_v004/coordinator_pid'
if pid_path.exists():
 pid=pid_path.read_text().strip()
 if not pid.isdigit():raise ValueError('Invalid registered coordinator PID')
 print('\nCOORDINATOR_PROCESS',flush=True)
 result=subprocess.run(['ps','-p',pid,'-o','pid,etimes,args'],capture_output=True,text=True,timeout=20)
 print(result.stdout,flush=True)
 print('PS_EXIT_CODE='+str(result.returncode),flush=True)
jobs=[]
for relative in ('control/preflight_v004_job_id','control/resource_pilot_v004_job_id'):
 p=root/relative
 if p.exists():jobs.append(p.read_text().strip())
p=root/'control/full_v004/jobs.json'
if p.exists():jobs.extend(str(x) for x in json.loads(p.read_text()).values())
if any(not x.isdigit() for x in jobs):raise ValueError('Invalid task job registry')
if jobs:
 print('\nREGISTERED_V004_SCHEDULER',flush=True)
 result=subprocess.run(['sacct','-j',','.join(jobs),'-n','-P','-o','JobID,State,ExitCode,Elapsed,MaxRSS,NodeList'],capture_output=True,text=True,timeout=60,check=True)
 print(result.stdout,flush=True)
for relative in ('logs/continuation-v004.log','control/continuation_v004/events.jsonl'):
 p=root/relative
 print('\nTAIL '+relative,flush=True)
 if p.exists():print('\n'.join(p.read_text().splitlines()[-15:]),flush=True)
 else:print('NOT_CREATED',flush=True)
for relative in ('control/preflight_v004_job_id','control/resource_pilot_v004_job_id'):
 p=root/relative
 if not p.exists():continue
 job=p.read_text().strip()
 prefix='preflight' if 'preflight_' in relative else 'resource-pilot'
 for extension in ('out','err'):
  log=root/'logs'/f'{prefix}-{job}.{extension}'
  print('\nTAIL '+str(log.relative_to(root)),flush=True)
  if log.exists():
   print(json.dumps({'bytes':log.stat().st_size,'mtime_ns':log.stat().st_mtime_ns}),flush=True)
   with log.open('rb') as f:
    f.seek(max(0,log.stat().st_size-16000));print(f.read().decode(errors='replace'),flush=True)
  else:print('NOT_CREATED',flush=True)
PY
