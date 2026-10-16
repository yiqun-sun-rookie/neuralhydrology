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
