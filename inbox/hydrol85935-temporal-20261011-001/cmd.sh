#!/bin/bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - <<'IMPORT_FIVE'
from pathlib import Path
import json,hashlib,tarfile,subprocess,datetime,os
R=Path('/data1/home/sunyiq/hydrol85935_temporal_attempts/hpc_v009_001/hydrol85935_temporal_persistence_20261011_001')
T=R/'attempts/infeasible_recovery_v002_20261015_001';H=R/'control/local_s100_backfill_20261017_001';I=H/'import_001'
P=Path('/data1/home/sunyiq/hpc_mailbox/inbox/hydrol85935-temporal-20261011-001/payload')/'local_s100_import_20261017_001_666d709812e5.tar.gz'
read=lambda p:json.loads(p.read_text())
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
digest=lambda v:hashlib.sha256(json.dumps(v,sort_keys=True,ensure_ascii=False,allow_nan=False).encode()).hexdigest()
def now():return datetime.datetime.now(datetime.timezone.utc).isoformat()
def new(p,v):
 with p.open('x') as f:json.dump(v,f,indent=2);f.flush();os.fsync(f.fileno())
def detail():return subprocess.check_output(['scontrol','show','job','242753','-o'],text=True,timeout=30)
def check(d):
 assert 'JobState=PENDING' in d and 'Reason=JobHeldUser' in d and 'RunTime=00:00:00' in d,d
 assert 'Command='+str(T/'submissions/s100_missing.sbatch') in d and 'WorkDir='+str(T) in d,d
 assert 'afterok:242752' in d and 'NumCPUs=4' in d and 'TresPerNode=gpu:1' in d and 'Partition=hgpu2p' in d,d
assert not I.exists(),'Import already attempted; reconcile exact intent, never replay release'
assert P.stat().st_size==851966 and sha(P)=='666d709812e5ae231b57e5830340f6595a0664df7ec2537e571984642ee545d6'
assert sha(H/'assignment.json')=='720597701f18d65f73461a2585853a6bdae2397cf20e8598adfd531d971ea24a'
a=read(H/'assignment.json');conf=read(H/'confirmation.json')
assert conf['state']=='HPC_WITHDRAWN_LOCAL_OWNS_FIVE' and conf['basins']==a['basins'] and conf['assignment_sha256']==sha(H/'assignment.json')
assert sha(T/'assignment.json')==a['old_assignment_sha256'] and sha(T/'recover.py')=='eb443b9df4353205fe921e2ea07fda316cb631bfcc91f6ce4a4d6ec8b066d35e'
assert sha(T/'submissions/s100_missing.sbatch')=='11cd2f1f1b58a1eef0224aa69424a4178c99b7efa15ad1eb90ec8db1c9c1d9cf'
parent=Path('/data1/home/sunyiq/hydrol85935_revision_20261008_001')
assert sha(parent/'control/hybrid_v024_20261014_001/assignment.json')=='3123b2103afbdfea383ba710cb429e07fa4e68a56bb75f9b0c28eee757addbd0'
assert sha(parent/'control/hybrid_v009_20261012_001/worker.py')=='df0b4975402981850b889b578ee76a09c1b9c6fb18475a2be0108e1c00a61d6c'
before=detail();check(before)
with tarfile.open(P,'r:gz') as tf:
 members=tf.getmembers();assert len(members)==16 and len({m.name for m in members})==16
 raw={m.name:tf.extractfile(m).read() for m in members if m.isfile()}
 assert len(raw)==16 and hashlib.sha256(raw['provenance.json']).hexdigest()=='9004b4cb40b90fc9e461b0fea399f9ef2d7a975248543b9a49343b868aaf23e7'
 manifest=json.loads(raw['provenance.json']);assert set(raw)==set(manifest['files'])|{'provenance.json'}
 assert manifest['assignment_sha256']==sha(H/'assignment.json') and manifest['basins']==a['basins'] and manifest['local_config_sha256']==a['local_config_sha256']
 assert manifest['formal_complete']['unknown_failures']==0 and manifest['worker_exit']['exit_code']==0 and manifest['formal_complete']['search_records']==10
 expected={f'records/single_temperature_s100/{b}/{n}' for b in a['basins'] for n in ['arrays.npz','metadata.json','complete.json']}
 assert set(manifest['files'])==expected
 idx=read(parent/'execution/hpc_v009/frozen/training_assets/s100.json')
 old_model=read(next((R/'records/single_temperature_s100').glob('*/metadata.json')))['identity']['model']
 for n,v in manifest['files'].items():assert len(raw[n])==v['bytes'] and hashlib.sha256(raw[n]).hexdigest()==v['sha256'],n
 for b in a['basins']:
  rel=f'records/single_temperature_s100/{b}/';md=json.loads(raw[rel+'metadata.json']);mark=json.loads(raw[rel+'complete.json']);identity=md['identity']
  assert identity==manifest['identities'][b] and identity['manifest_sha256']==a['scientific_manifest_sha256'] and identity['seed']==100 and identity['basin_id']==b
  assert identity['model']==old_model
  assert identity['model']['asset_index_sha256']==digest(idx) and identity['model']['epoch']==30
  for key in ['config','weight','scaler']:assert identity['model'][key+'_sha256']==idx['assets'][key]['sha256']
  assert mark['identity_sha256']==digest(identity) and mark['status']=='complete'
  assert mark['arrays_sha256']==manifest['files'][rel+'arrays.npz']['sha256'] and mark['metadata_sha256']==manifest['files'][rel+'metadata.json']['sha256']
  assert md['details']['execution_endpoint']=='LOCAL' and md['details']['exclusive_assignment_sha256']==a['local_config_sha256']
  for root in [R,T]:
   assert not (root/'records/single_temperature_s100'/b).exists(),b
   assert not (root/'failures/records/single_temperature_s100'/(b+'.json')).exists(),b
I.mkdir();new(I/'intent.json',dict(utc=now(),payload=str(P),payload_sha256='666d709812e5ae231b57e5830340f6595a0664df7ec2537e571984642ee545d6',payload_bytes=851966,provenance_sha256='9004b4cb40b90fc9e461b0fea399f9ef2d7a975248543b9a49343b868aaf23e7',before=before,only_job_to_release=242753))
for name,data in raw.items():
 p=I/name;p.parent.mkdir(parents=True,exist_ok=True)
 with p.open('xb') as f:f.write(data);f.flush();os.fsync(f.fileno())
for n,v in manifest['files'].items():
 p=T/n;p.parent.mkdir(parents=True,exist_ok=True)
 with p.open('xb') as f:f.write(raw[n]);f.flush();os.fsync(f.fileno())
 assert sha(p)==v['sha256'] and p.stat().st_size==v['bytes'],n
for n,v in manifest['files'].items():assert sha(T/n)==v['sha256'] and sha(I/n)==v['sha256']
complete=dict(status='FIVE_LOCAL_PAIRS_IMPORTED_IDENTICAL_BYTES',utc=now(),files=15,pairs=5,search_records=10,payload_sha256='666d709812e5ae231b57e5830340f6595a0664df7ec2537e571984642ee545d6',provenance_sha256='9004b4cb40b90fc9e461b0fea399f9ef2d7a975248543b9a49343b868aaf23e7',assignment_sha256=sha(H/'assignment.json'),target=str(T),local_endpoint_preserved=True,numerical_recheck='On compute node in existing 242753 and 242754 before any reuse; no login-node numerical computation')
new(I/'import_complete.json',complete);print('LOCAL_IMPORT_COMPLETE '+json.dumps(complete),flush=True)
ready=detail();check(ready);new(I/'release_intent.json',dict(utc=now(),job=242753,before=ready,import_complete_sha256=sha(I/'import_complete.json')))
r=subprocess.run(['scontrol','release','242753'],capture_output=True,text=True,timeout=30)
new(I/'release_response.json',dict(exit_code=r.returncode,stdout=r.stdout,stderr=r.stderr,utc=now()));assert r.returncode==0,r.stderr
after=detail();assert 'Reason=JobHeldUser' not in after and 'JobState=PENDING' in after and 'afterok:242752' in after,after
confirm=dict(status='IMPORTED_AND_BACKFILL_RELEASED_TO_ORIGINAL_DEPENDENCY',job=242753,after=after,utc=now(),import_complete_sha256=sha(I/'import_complete.json'),payload_sha256='666d709812e5ae231b57e5830340f6595a0664df7ec2537e571984642ee545d6')
new(I/'release_confirmation.json',confirm);print('LOCAL_IMPORT_RELEASE '+json.dumps(confirm),flush=True)

IMPORT_FIVE
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
