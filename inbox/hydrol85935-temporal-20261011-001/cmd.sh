#!/bin/bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - <<'PY'
from pathlib import Path
import json,hashlib,subprocess,collections
r=Path('/data1/home/sunyiq/hydrol85935_temporal_attempts/hpc_v009_001/hydrol85935_temporal_persistence_20261011_001')
p=Path('/data1/home/sunyiq/hydrol85935_revision_20261008_001')
a=p/'control/hybrid_v016_20261014_001/assignment.json'
assert hashlib.sha256(a.read_bytes()).hexdigest()=='45f14903b0ecc33f7013ab1bcf5bb3abd2e27849934ef2a9bb818cb1e208eb58'
v=json.loads(a.read_text())
assert v['hpc_training_seeds']==[100,200,300]
assert v['scientific_code']==str(p/'versions/v004/code') and v['output']==str(p/'execution/hpc_v009')
print('SOURCE '+json.dumps({k:v.get(k) for k in ['version','hpc_training_seeds','scientific_code','output']}),flush=True)
c=r/'control/queue_priority_20261014_001'
assert hashlib.sha256((c/'queue_priority.py').read_bytes()).hexdigest()=='a3de8ee97281cb5b1ff7ab745bd8b4506abf3da932d35869b08eec3d0631fe6e'
reg=json.loads((c/'watcher_registration.json').read_text()); proc=Path('/proc')/str(reg['pid'])
alive=False
if proc.exists():
 alive=(proc.joinpath('stat').read_text().split()[21]==reg['proc_start_ticks'] and proc.joinpath('cmdline').read_bytes().split(b'\0')[:-1]==[s.encode() for s in reg['command']])
print('WATCHER '+json.dumps({'alive':alive,'registration':reg,'status':json.loads((c/'status.json').read_text())}),flush=True)
submissions=[json.loads(p.read_text()) for p in sorted((r/'control/submissions').glob('*.json')) if not p.name.endswith('.attempt.json')]
print('SUBMISSIONS '+json.dumps(submissions),flush=True)
own_ids={str(v['job_id']) for v in submissions}
q=subprocess.run(['squeue','-r','-h','-u','sunyiq','-o','%i|%T|%M|%r|%C|%b|%N'],capture_output=True,text=True,timeout=45,check=True)
rows=[line.split('|') for line in q.stdout.splitlines()]
own=[row for row in rows if row[0].split('_')[0] in own_ids]
held=json.loads((c/'applied.json').read_text())
print('QUEUE '+json.dumps({'own_rows':own,'parent_pending_by_reason':dict(collections.Counter(row[3] for row in rows if row[0].split('_')[0] in {'241336','241337','241344'}))}),flush=True)
if own_ids:
 a=subprocess.run(['sacct','-j',','.join(sorted(own_ids)),'-n','-P','--format=JobID,State,ElapsedRaw,Start,End,ExitCode,NodeList'],capture_output=True,text=True,timeout=45)
 print('ACCOUNTING '+json.dumps({'rc':a.returncode,'stdout':'\n'.join(line for line in a.stdout.splitlines() if '.' not in line.split('|')[0]),'stderr':a.stderr}),flush=True)
for row in own:
 if row[1] in {'RUNNING','COMPLETING'}:
  p=subprocess.run(['scontrol','show','job',row[0]],capture_output=True,text=True,timeout=45)
  print('ACTIVE_JOB '+json.dumps({'job_id':row[0],'rc':p.returncode,'stdout':p.stdout,'stderr':p.stderr}),flush=True)
for name in ['control/new_models_verified.json','control/resource_pilot.json','reports/coverage_and_summary.json','control/queue_priority_20261014_001/parent_released.json']:
 p=r/name
 if p.exists():print('RESULT '+json.dumps({'path':name,'value':json.loads(p.read_text())}),flush=True)
print('RECORD_COUNTS '+json.dumps({'formal_pairs_by_seed':{str(seed):sum(1 for _ in (r/'records'/f'single_temperature_s{seed}').glob('*/complete.json')) for seed in [100,200,300]},'pilot_pairs':sum(1 for _ in (r/'pilot').glob('*/*/complete.json'))}),flush=True)
for p in sorted((r/'failures').glob('*/*/*.json')):
 print('FAILURE '+json.dumps({'path':str(p.relative_to(r)),'value':json.loads(p.read_text())}),flush=True)
PY
