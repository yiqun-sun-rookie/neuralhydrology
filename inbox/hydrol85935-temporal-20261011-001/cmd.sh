#!/bin/bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - <<'PY'
import json, subprocess, hashlib, time
from pathlib import Path
p=Path('/data1/home/sunyiq/hydrol85935_revision_20261008_001')
r=Path('/data1/home/sunyiq/hydrol85935_temporal_attempts/hpc_v009_001/hydrol85935_temporal_persistence_20261011_001')
o=p/'execution/hpc_v009'
a=p/'control/hybrid_v013_20261014_001/assignment.json'
assert hashlib.sha256(a.read_bytes()).hexdigest()=='dacdf8b29545581d27f148aff65153458c9a063f6915635da64937cdb8503db2'
t=json.loads(a.read_text())['hpc_tasks'][6]
print('CHECK_TIME '+json.dumps({'unix':time.time(),'task':t}),flush=True)
for tag,cmd in [('JOB',['scontrol','show','job','241336_6']),('PREFLIGHT_JOB',['scontrol','show','job','241345']),('ACCOUNTING',['sacct','-j','241336','-n','-P','--format=JobID,State,ElapsedRaw,Start,End,ExitCode,NodeList'])]:
 x=subprocess.run(cmd,capture_output=True,text=True,timeout=45)
 lines=x.stdout.splitlines()
 if tag=='ACCOUNTING':lines=[z for z in lines if z.split('|')[0] in ['241336_'+str(k) for k in range(7)]]
 print(tag+' '+json.dumps({'rc':x.returncode,'stdout':'\n'.join(lines),'stderr':x.stderr[-1500:]}),flush=True)
completed=[]; by_basin=[]
for basin in t['basins']:
 n=0
 for combo in t['combinations']:
  d=o/'records/attacks'/combo/basin
  if (d/'complete.json').is_file():
   n+=1
   meta=json.loads((d/'metadata.json').read_text())
   completed.append({'basin':basin,'combination':combo,'mtime':(d/'complete.json').stat().st_mtime,'details':{k:v for k,v in meta.get('details',{}).items() if any(s in k for s in ['wall','time','second','duration'])}})
 by_basin.append({'basin':basin,'completed':n,'expected':len(t['combinations'])})
print('TASK_PROGRESS '+json.dumps({'completed':len(completed),'expected':len(t['basins'])*len(t['combinations']),'by_basin':by_basin,'recent':sorted(completed,key=lambda x:x['mtime'])[-15:]}),flush=True)
for ext in ['out','err']:
 q=p/('control/hybrid_v009_20261012_001/logs/attacks-241336_6.'+ext)
 if q.is_file():
  with q.open('rb') as f:f.seek(max(0,q.stat().st_size-6000));v=f.read().decode(errors='replace')
  print('LOG_TAIL '+json.dumps({'path':str(q),'mtime':q.stat().st_mtime,'tail':v}),flush=True)
for seed in [100,200,300]:
 ip=o/f'frozen/training_assets/s{seed}.json'
 idx=json.loads(ip.read_text());run=o/idx['run_relative_path']
 files=[]
 for name,v in idx['assets'].items():
  q=run/v['relative_path']
  if not q.exists():q=o/v['relative_path']
  files.append({'name':name,'path':str(q),'exists':q.exists(),'size':q.stat().st_size if q.exists() else None,'index':v})
 tests=[{'path':str(q.relative_to(o)),'size':q.stat().st_size} for q in run.glob('test/**/*') if q.is_file() and q.name in ['test_results.p','test_metrics.csv']]
 print('MODEL_ASSETS '+json.dumps({'seed':seed,'index':idx,'files':files,'test_files':tests}),flush=True)
c=r/'control/queue_priority_20261014_001'
print('COORDINATOR_STATUS '+(c/'status.json').read_text(),flush=True)
print('OWN_SUBMISSIONS '+json.dumps([json.loads(q.read_text()) for q in sorted((r/'control/submissions').glob('*.json')) if not q.name.endswith('.attempt.json')]),flush=True)
PY
