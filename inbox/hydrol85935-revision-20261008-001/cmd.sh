#!/bin/bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - "$HOME/hpc_mailbox/inbox/hydrol85935-revision-20261008-001/payload/workflow_v010_20261012_001.tar.gz" <<'PY'
import hashlib,json,tarfile,subprocess,re,sys
from pathlib import Path
parent=Path('/data1/home/sunyiq/hydrol85935_revision_20261008_001');folder=Path('/data1/home/sunyiq/hydrol85935_revision_20261008_001/control/workflow_v010_20261012_001');temporal=Path('/data1/home/sunyiq/hydrol85935_temporal_attempts/hpc_v009_001/hydrol85935_temporal_persistence_20261011_001')
payload=Path(sys.argv[1]);assert hashlib.sha256(payload.read_bytes()).hexdigest()=='0ad84c7507738c87cd51e0dc3a0f3f1324e80ed7817609d214d713cb503976fb'
assert parent.resolve()==parent and (parent/'OWNER').read_text().strip()=='hydrol85935_revision_20261008_001'
assert not folder.exists() and not temporal.exists(), 'Preserve existing attempt, do not redeploy or resubmit'
old=Path('/data1/home/sunyiq/hydrol85935_temporal_persistence_20261011_001')
assert not list((old/'control/submissions').glob('*.attempt.json')) and not list((old/'control/submissions').glob('*.json')), 'Reconcile existing additional submissions'
expected={'train':241335,'attacks':241336,'validate':241337}
assert json.loads((parent/'control/hybrid_v009_20261012_001/jobs.json').read_text())==expected
before={}
for stage,jid in expected.items():
 r=subprocess.run(['scontrol','show','job','-o',str(jid)],capture_output=True,text=True,timeout=30,check=True)
 for token in [f'Command={parent}/control/hybrid_v009_20261012_001/{stage}.sbatch ',f'WorkDir={parent}/control/hybrid_v009_20261012_001 ', 'JobState=PENDING ']:assert token in r.stdout,token
 before[stage]=r.stdout
for stage,jid in {'train':240076,'attacks':240077,'report':240078}.items():
 r=subprocess.run(['scontrol','show','job','-o',str(jid)],capture_output=True,text=True,timeout=30,check=True)
 for token in [f'Command={parent}/control/full_v004/{stage}.sbatch ',f'WorkDir={parent}/control/continuation_v004 ','JobState=PENDING ','Reason=JobHeldUser ','Priority=0 ']:assert token in r.stdout,token
before['old_temporal_root']=str(old)
with tarfile.open(payload,'r:gz') as t:
 contents={m.name:t.extractfile(m).read() for m in t.getmembers() if m.isfile()}
 assert len(contents)==len(t.getmembers())
 inventory=json.loads(contents.pop('payload_inventory.json'))
 assert set(inventory)==set(contents)
 for name,data in contents.items():
  assert hashlib.sha256(data).hexdigest()==inventory[name]
  prefix,rel=name.split('/',1);assert prefix in ('parent','temporal')
  root=folder if prefix=='parent' else temporal
  path=root/rel;assert path.resolve().is_relative_to(root.resolve())
  path.parent.mkdir(parents=True,exist_ok=True)
  with path.open('xb') as f:f.write(data)
# Compare all temporal scientific bytes with the previously deployed experiment.
for rel in ['code/protocol.json']+['code/temporal_20261011/'+n for n in ['__init__.py','core.py','storage.py','run.py']]:
 assert (temporal/rel).read_bytes()==(old/rel).read_bytes(),rel
def save(path,value):
 path.parent.mkdir(parents=True,exist_ok=True)
 with path.open('x') as f:json.dump(value,f,indent=2)
save(folder/'before.json',before)
save(folder/'export_submission.attempt.json',{'dependency':241337,'script_sha256':hashlib.sha256((folder/'export.sbatch').read_bytes()).hexdigest()})
r=subprocess.run(['sbatch',str(folder/'export.sbatch')],capture_output=True,text=True,timeout=120)
text=r.stdout+r.stderr;(folder/'export_submission.txt').write_text(text);print(text,flush=True)
ids=re.findall(r'(?m)^Submitted batch job ([0-9]+)$',text);assert r.returncode==0 and len(ids)==1,'Unknown submit outcome; do not retry'
export=int(ids[0]);save(folder/'jobs.json',{'export':export})
binding={'parent_code_version':'v004','parent_execution_version':'hpc_v009','parent_execution':str(parent/'execution/hpc_v009'),'serial_dependency_job':export,
 'parent_training_job':241335,'parent_validation_job':241337,'assignment_sha256':hashlib.sha256((folder/'assignment.json').read_bytes()).hexdigest(),
 'models_validated':False,'status':'QUEUED_BINDING_REQUIRES_ACTUAL_TRAINING_ASSETS_AND_12_INTERFACE_CHECKS','new_model_interface_tolerance':0.00001}
save(temporal/'control/parent_binding_v010.json',binding)
(temporal/'logs').mkdir(exist_ok=True)
r=subprocess.run([sys.executable,str(temporal/'code/temporal_hpc_v010.py'),'--root',str(temporal),'--parent',str(parent),'--register-after',str(export)],capture_output=True,text=True,timeout=180)
(folder/'temporal_registration.txt').write_text(r.stdout+r.stderr);print(r.stdout+r.stderr,flush=True)
assert r.returncode==0,'Unknown temporal submission outcome; preserve all attempts'
preflight=json.loads((temporal/'control/submissions/preflight.json').read_text())
save(folder/'registration.json',{'export_job':export,'temporal_preflight_job':preflight['job_id'],'temporal_root':str(temporal),'parent_jobs_unchanged':True,'scientific_rules_changed':False})
print('WORKFLOW_V010 '+(folder/'registration.json').read_text(),flush=True)

PY
