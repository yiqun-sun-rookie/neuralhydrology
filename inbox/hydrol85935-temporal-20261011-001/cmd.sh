#!/bin/bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - <<'PY'
from pathlib import Path
import io,zipfile,json,hashlib,base64,subprocess
r=Path('/data1/home/sunyiq/hydrol85935_temporal_attempts/hpc_v009_001/hydrol85935_temporal_persistence_20261011_001')
files=[]
pilot=json.loads((r/'control/resource_pilot.json').read_text())
assert pilot['status']=='PASS' and pilot['scheduler_job_id']=='241345'
for i,seed in enumerate([100,200,300]):
 d=r/'pilot'/f'single_temperature_s{seed}'/'01022500'
 marker=(d/'complete.json').read_bytes()
 assert hashlib.sha256(marker).hexdigest()==pilot['record_complete_sha256'][i]
 v=json.loads(marker)
 for filename,key in [('arrays.npz','arrays_sha256'),('metadata.json','metadata_sha256')]:
  assert hashlib.sha256((d/filename).read_bytes()).hexdigest()==v[key]
 files.extend([d/'complete.json',d/'arrays.npz',d/'metadata.json'])
files.extend([r/'control/resource_pilot.json',r/'control/new_models_verified.json',r/'frozen/manifest.json',r/'control/parent_binding_v010.json'])
index={str(p.relative_to(r)):{'size':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in files}
stream=io.BytesIO()
with zipfile.ZipFile(stream,'w',compression=zipfile.ZIP_DEFLATED) as z:
 for p in files:z.writestr(str(p.relative_to(r)),p.read_bytes())
payload=stream.getvalue()
print('EXPORT_INDEX '+json.dumps(index),flush=True)
print('EXPORT_ARCHIVE '+json.dumps({'bytes':len(payload),'sha256':hashlib.sha256(payload).hexdigest(),'scope':'existing saved pilot records and frozen provenance only; no prediction or scientific computation'}),flush=True)
print('EXPORT_BASE64 '+base64.b64encode(payload).decode('ascii'),flush=True)
subs=[json.loads(p.read_text()) for p in sorted((r/'control/submissions').glob('*.json')) if not p.name.endswith('.attempt.json')]
print('SUBMISSIONS '+json.dumps(subs),flush=True)
ids=','.join(str(s['job_id']) for s in subs)
for tag,cmd in [('QUEUE',['squeue','-r','-h','-j',ids,'-o','%i|%T|%M|%r|%C|%b|%N']),('ACCOUNTING',['sacct','-j',ids,'-n','-P','--format=JobID,State,ElapsedRaw,Start,End,ExitCode,NodeList']),('MAIN_JOB_IDENTITY',['scontrol','show','job','242488'])]:
 p=subprocess.run(cmd,capture_output=True,text=True,timeout=45)
 print(tag+' '+json.dumps({'rc':p.returncode,'stdout':p.stdout,'stderr':p.stderr}),flush=True)
print('RECORD_COUNTS '+json.dumps({'formal_pairs':sum(1 for _ in (r/'records').glob('*/*/complete.json')),'pilot_pairs':sum(1 for _ in (r/'pilot').glob('*/*/complete.json'))}),flush=True)
PY
