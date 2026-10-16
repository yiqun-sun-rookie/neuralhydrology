#!/bin/bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - <<'HANDOFF'
import json,hashlib,subprocess,base64,datetime
from pathlib import Path
R=Path('/data1/home/sunyiq/hydrol85935_temporal_attempts/hpc_v009_001/hydrol85935_temporal_persistence_20261011_001');T=Path('/data1/home/sunyiq/hydrol85935_temporal_attempts/hpc_v009_001/hydrol85935_temporal_persistence_20261011_001/attempts/infeasible_recovery_v002_20261015_001');H=Path('/data1/home/sunyiq/hydrol85935_temporal_attempts/hpc_v009_001/hydrol85935_temporal_persistence_20261011_001/control/local_s100_backfill_20261017_001')
A=base64.b64decode('ew0KICAiaWQiOiAibG9jYWxfczEwMF9iYWNrZmlsbF8yMDI2MTAxN18wMDEiLA0KICAic2VlZCI6IDEwMCwNCiAgImJhc2lucyI6IFsNCiAgICAiMDQyMTY0MTgiLA0KICAgICIwNDIyMTAwMCIsDQogICAgIjA0MjI0Nzc1IiwNCiAgICAiMDQyMzMwMDAiLA0KICAgICIwNDI1NjAwMCINCiAgXSwNCiAgIm93bmVyIjogIkxPQ0FMIiwNCiAgInNlYXJjaF9yZWNvcmRzIjogMTAsDQogICJoZWxkX2pvYiI6IDI0Mjc1MywNCiAgIm9sZF9hc3NpZ25tZW50X3NoYTI1NiI6ICIxMGI0NDRmZDFhMTUyNTIzNmUzZGJhNGZhOTQwOGNjYTg2ZTgxMjc1ZWViOGE4YzVhYjA1ZWFkOTA2MmZhNjNmIiwNCiAgImxvY2FsX291dHB1dCI6ICJHOlxcaHlkcm9sODU5MzVfdGVtcG9yYWxfbG9jYWxfMjAyNjEwMTRfMDAxXFxoeWRyb2w4NTkzNV9yZXZpc2lvbl8yMDI2MTAwOF8wMDFfYnJpZGdlXFxoeWRyb2w4NTkzNV90ZW1wb3JhbF9wZXJzaXN0ZW5jZV8yMDI2MTAxMV8wMDFcXGF0dGVtcHRzXFxsb2NhbF9zMTAwX2JhY2tmaWxsXzIwMjYxMDE3XzAwMSIsDQogICJsb2NhbF9jb25maWdfc2hhMjU2IjogIjVkZWJkZDk5Nzg3MzRjOWRmOTliZTFhYTg5ODNmMGNkZWIzNWEzMDc2ZTdmMjFmMDNlNmFmMWMzOThkYTkwYzQiLA0KICAibG9jYWxfd29ya2VyX3NoYTI1NiI6ICIyODdhNzE2YmJlZTdmMGUyOWM5YTk1MmMwNDVmOTYzMjBmNzc1MDU1NzgzNThkNTVmZjE4ZjRiNjVlYjA2ZWYyIiwNCiAgInNjaWVudGlmaWNfbWFuaWZlc3Rfc2hhMjU2IjogIjVjOWQ1M2NiYWM5ZDllZTViNjIyZGYyYTAwZWNhMTM4ZTBlYThlZGZkYjk5YTEwNDcwMTVkMjMyZGEwNTVhODkiLA0KICAia25vd25fdW5jb21wdXRhYmxlX3JldGFpbmVkX29uX2hwYyI6IFsNCiAgICAiMDQyMTMwNzUiDQogIF0sDQogICJzY29wZV91bmNoYW5nZWQiOiAzMTg2LA0KICAicmVsZWFzZV9jb25kaXRpb24iOiAiQWxsIGZpdmUgY29tcGxldGUgcGFpcnMgdmFsaWRhdGVkLCBpbXBvcnRlZCBieXRlLWZvci1ieXRlIGludG8gb3JpZ2luYWwgcmVjb3ZlcnkgdGFyZ2V0LCB2YWxpZGF0ZWQgdGhlcmUsIG5vIG1pc3Npbmcgb3IgZmFpbGVkIHBhaXI7IG9ubHkgdGhlbiByZWxlYXNlIDI0Mjc1MyB0byByZXVzZSBvdXRwdXRzIGFuZCBjbGFzc2lmeSAwNDIxMzA3NS4gTmV2ZXIgcmVsZWFzZSBiYXNlZCBvbmx5IG9uIGxvY2FsIHByb2Nlc3MgZXhpdC4iDQp9');a=json.loads(A)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def new(p,v):
 with p.open('x') as f:json.dump(v,f,indent=2)
def detail():return subprocess.check_output(['scontrol','show','job','242753','-o'],text=True)
def check(d):
 assert 'JobState=PENDING' in d and 'RunTime=00:00:00' in d,d
 assert 'Command='+str(T/'submissions/s100_missing.sbatch') in d,d
 assert 'WorkDir='+str(T) in d and 'afterok:242752' in d,d
 assert 'StartTime=Unknown' in d or 'Reason=Dependency' in d or 'Reason=JobHeldUser' in d,d
 for basin in a['basins']:
  for root in [R,T]:
   assert not (root/'records/single_temperature_s100'/basin).exists(),basin
   assert not (root/'failures/records/single_temperature_s100'/(basin+'.json')).exists(),basin
assert not H.exists(),'Handoff exists; reconcile, never replay'
assert sha(T/'assignment.json')==a['old_assignment_sha256']
assert sha(T/'submissions/s100_missing.sbatch')=='11cd2f1f1b58a1eef0224aa69424a4178c99b7efa15ad1eb90ec8db1c9c1d9cf'
before=detail();check(before)
H.mkdir();(H/'assignment.json').write_bytes(A)
new(H/'hold_intent.json',dict(job=242753,before=before,utc=datetime.datetime.now(datetime.timezone.utc).isoformat()))
p=subprocess.run(['scontrol','hold','242753'],capture_output=True,text=True)
new(H/'hold_response.json',dict(exit_code=p.returncode,stdout=p.stdout,stderr=p.stderr));assert p.returncode==0,p.stderr
after=detail();check(after);assert 'Reason=JobHeldUser' in after,after
confirmation=dict(state='HPC_WITHDRAWN_LOCAL_OWNS_FIVE',basins=a['basins'],held_job=242753,seed=100,assignment_sha256=sha(H/'assignment.json'),before=before,after=after,utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),local_output=a['local_output'],local_worker_sha256=a['local_worker_sha256'],local_config_sha256=a['local_config_sha256'])
new(H/'confirmation.json',confirmation)
print('LOCAL_HANDOFF '+json.dumps(confirmation),flush=True)

HANDOFF
#!/bin/bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - <<'GPU_AVAILABILITY'
import subprocess,json,datetime
for label,args in [
 ('GPU_GRES_USED',['sinfo','-N','-p','hgpu2p,hgpu2,hgpu4,hgpu8','-O','nodelist:16,partition:12,statelong:18,gres:18,gresused:30,cpusstate:24']),
 ('GPU_NODE_RAW',['scontrol','show','node','ngu[001-011,101-104,201-203]','-o']),
 ('GPU_QOS',['sacctmgr','-n','-P','show','qos','qos_sunyiq']),
 ('GPU_START_NOW',['squeue','--start','-j','242752','-o','%.22i|%.12T|%.24S|%.30r|%.24N'])]:
 try:
  r=subprocess.run(args,capture_output=True,text=True,timeout=25)
  print(label+' '+json.dumps(dict(utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),args=args,exit_code=r.returncode,stdout=r.stdout,stderr=r.stderr)),flush=True)
 except Exception as ex:print(label+' '+json.dumps(dict(error=type(ex).__name__+': '+str(ex))),flush=True)
GPU_AVAILABILITY
#!/bin/bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - <<'READ_SOURCE'
from pathlib import Path
import json,hashlib,re
r=Path('/data1/home/sunyiq/hydrol85935_revision_20261008_001')
p=r/'control/hybrid_v009_20261012_001/worker.py'
b=p.read_bytes();t=b.decode()
print('CURRENT_PARENT_FORWARDER '+json.dumps(dict(path=str(p),sha256=hashlib.sha256(b).hexdigest(),text=t[:5000])),flush=True)
match=re.search(r"p=Path\('([^']+)'\)",t)
if match:
 target=Path(match[1]);assert target.is_relative_to(r/'control')
 data=target.read_bytes();a=target.parent/'assignment.json';v=json.loads(a.read_text())
 print('CURRENT_PARENT_ASSIGNMENT '+json.dumps(dict(target=str(target),worker_sha256=hashlib.sha256(data).hexdigest(),assignment_sha256=hashlib.sha256(a.read_bytes()).hexdigest())),flush=True)
READ_SOURCE
#!/bin/bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - <<'PY'
from pathlib import Path
import json,hashlib,subprocess,collections,datetime,socket
r=Path('/data1/home/sunyiq/hydrol85935_temporal_attempts/hpc_v009_001/hydrol85935_temporal_persistence_20261011_001')
d=r/'attempts/infeasible_recovery_v002_20261015_001'
def read(p):return json.loads(p.read_text())
def emit(label,v):print(label+' '+json.dumps(v),flush=True)
def call(args):return subprocess.run(args,capture_output=True,text=True,timeout=60,check=True).stdout
manifest=read(d/'payload_manifest.json')
for name,digest in manifest.items():
 assert hashlib.sha256((d/name).read_bytes()).hexdigest()==digest,name
reg=read(d/'registered.json')
emit('RECOVERY_REGISTRATION',reg)
emit('RECOVERY_ASSIGNMENT',dict(sha256=hashlib.sha256((d/'assignment.json').read_bytes()).hexdigest()))
ids=[str(j['job_id']) for j in reg['jobs']]
emit('SCHEDULER_SAMPLE',dict(started_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),host=socket.gethostname()))
q=call(['squeue','-r','-h','-u','sunyiq','-o','%i|%T|%M|%r|%C|%b|%N'])
rows=[x.split('|') for x in q.splitlines()]
own=[x for x in rows if x[0].split('_')[0] in set(ids)]
held=set(read(r/'control/queue_priority_20261014_001/applied.json')['held_parent_ids'])
emit('RECOVERY_QUEUE',dict(own=own,parent_by_state_reason=dict(collections.Counter(x[1]+'/'+x[3] for x in rows if x[0] in held))))
a=call(['sacct','-j',','.join(ids+['242488','242597']),'-n','-P','--format=JobID,State,ElapsedRaw,Start,End,ExitCode,NodeList'])
emit('RECOVERY_ACCOUNTING',dict(stdout='\n'.join(x for x in a.splitlines() if '.' not in x.split('|')[0])))
sampled=set()
for row in own:
 base=row[0].split('_')[0]
 if row[1] in {'RUNNING','COMPLETING'} or base not in sampled:
  emit('REGISTERED_JOB_DETAIL',dict(job_id=row[0],stdout=call(['scontrol','show','job',row[0]])))
  sampled.add(base)
emit('SCHEDULER_SAMPLE_END',dict(finished_utc=datetime.datetime.now(datetime.timezone.utc).isoformat()))
emit('RECOVERY_COUNTS',dict(old_pairs={str(s):len(list((r/f'records/single_temperature_s{s}').glob('*/complete.json'))) for s in (100,200,300)},
 new_pairs={str(s):len(list((d/f'records/single_temperature_s{s}').glob('*/complete.json'))) for s in (100,200,300)},
 uncomputable={str(s):[p.stem for p in (d/f'uncomputable/s{s}').glob('*.json')] for s in (100,200,300)}))
for p in sorted((d/'failures/records').glob('*/*.json')):emit('RECOVERY_FAILURE',dict(path=str(p),value=read(p)))
for p in sorted((d/'logs').glob('*.err')):
 if p.stat().st_size:
  raw=p.read_bytes();emit('RECOVERY_ERROR_LOG',dict(path=str(p),bytes=len(raw),tail=raw[-3500:].decode(errors='replace')))
report=d/'reports/coverage_and_summary.json'
if report.exists():emit('RECOVERY_REPORT',dict(sha256=hashlib.sha256(report.read_bytes()).hexdigest(),value=read(report)))
restored=r/'control/queue_priority_20261014_001/parent_released.json'
emit('PARENT_RELEASE',dict(exists=restored.exists(),value=read(restored) if restored.exists() else None))
PY
