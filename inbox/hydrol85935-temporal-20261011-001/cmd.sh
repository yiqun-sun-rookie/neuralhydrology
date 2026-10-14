#!/bin/bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - <<'PY'
import json,hashlib,subprocess,time
from pathlib import Path
r=Path('/data1/home/sunyiq/hydrol85935_temporal_attempts/hpc_v009_001/hydrol85935_temporal_persistence_20261011_001')
p=Path('/data1/home/sunyiq/hydrol85935_revision_20261008_001')
c=r/'control/queue_priority_20261014_001'
a=p/'control/hybrid_v015_20261014_001/assignment.json'
assert hashlib.sha256(a.read_bytes()).hexdigest()=='9b9fb20ffdc9256207d2e6c2e209bf9bb20ae3dcfba9e6b7cde1aef90ae59650'
v=json.loads(a.read_text())
print('SOURCE '+json.dumps({k:v.get(k) for k in ['version','hpc_training_seeds','scientific_code','output']}),flush=True)
reg=json.loads((c/'watcher_registration.json').read_text());proc=Path('/proc')/str(reg['pid'])
alive=proc.exists() and proc.joinpath('stat').read_text().split()[21]==reg['proc_start_ticks'] and str(c/'queue_priority.py').encode() in proc.joinpath('cmdline').read_bytes().split(b'\0')
print('WATCHER '+json.dumps({'alive':alive,'registration':reg,'status':json.loads((c/'status.json').read_text())}),flush=True)
subs=[json.loads(q.read_text()) for q in sorted((r/'control/submissions').glob('*.json')) if not q.name.endswith('.attempt.json')]
print('SUBMISSIONS '+json.dumps(subs),flush=True)
ids=['241336','241337','241344']+[str(x['job_id']) for x in subs]
for tag,cmd in [('QUEUE',['squeue','-r','-h','-j',','.join(ids),'-o','%i|%T|%M|%r']),('ACCOUNTING',['sacct','-j',','.join(ids),'-n','-P','--format=JobID,State,ElapsedRaw,Start,End,ExitCode,NodeList'])]:
 x=subprocess.run(cmd,capture_output=True,text=True,timeout=45)
 lines=x.stdout.splitlines()
 if tag=='ACCOUNTING':lines=[z for z in lines if not z.startswith('241336_') or z.startswith(('241336_6|','241336_7|'))]
 print(tag+' '+json.dumps({'rc':x.returncode,'stdout':'\n'.join(lines),'stderr':x.stderr}),flush=True)
for name in ['control/new_models_verified.json','control/resource_pilot.json','reports/coverage_and_summary.json','control/queue_priority_20261014_001/parent_released.json']:
 q=r/name
 if q.exists():print('RESULT '+json.dumps({'path':name,'value':json.loads(q.read_text())}),flush=True)
for q in sorted((r/'logs').glob('preflight-241345*')):
 if q.is_file():
  with q.open('rb') as f:f.seek(max(0,q.stat().st_size-12000));tail=f.read().decode(errors='replace')
  print('LOG '+json.dumps({'path':str(q),'size':q.stat().st_size,'tail':tail}),flush=True)
print('RECORD_COUNTS '+json.dumps({'formal_pairs':sum(1 for _ in (r/'records').glob('*/*/complete.json')),'pilot_pairs':sum(1 for _ in (r/'pilot').glob('*/*/complete.json'))}),flush=True)
PY
