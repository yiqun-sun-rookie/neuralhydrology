#!/usr/bin/env bash
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
python -B - <<'PY'
import datetime,hashlib,io,json,pathlib,subprocess,sys
import torch
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261012_recovery_003')
sys.path.insert(0,str(root))
from src.scheduler import code_identity
prep=json.loads((root/'records/recovery_preparation_complete.json').read_text())
jobs=json.loads((root/'records/scheduler_jobs.json').read_text())
assert prep['recovery_code_hash']==code_identity(root)
assert json.loads((root/'records/authorization.json').read_text())['code_hash']==code_identity(root)
def finite(x):
 if isinstance(x,torch.Tensor):return bool(torch.isfinite(x).all())
 if isinstance(x,dict):return all(finite(y) for y in x.values())
 if isinstance(x,(list,tuple)):return all(finite(y) for y in x)
 return True
def steps(x):return [float(v['step']) for v in x['optimizer']['state'].values()]
def tensors(x):
 if isinstance(x,torch.Tensor):return [x]
 if isinstance(x,dict):return sum([tensors(x[k]) for k in sorted(x,key=repr)],[])
 if isinstance(x,(list,tuple)):return sum([tensors(y) for y in x],[])
 return []
rows=[]
for m in prep['migrations']:
 rid=m['run'];source=pathlib.Path(m['source_root'])/'runs'/rid;target=root/'runs'/rid
 for name,expected in m['source_files'].items():assert hashlib.sha256((source/name).read_bytes()).hexdigest()==expected
 old=torch.load(source/'continuation.pt',map_location='cpu',weights_only=True)
 raw=(target/'continuation.pt').read_bytes();new=torch.load(io.BytesIO(raw),map_location='cpu',weights_only=True)
 n=len(old['values']);count=len(new['values']);assert count>=n
 for k in ['values','train_metrics','shuffle_hashes']:assert new[k][:n]==old[k]
 assert all(len(new[k])==count for k in ['values','train_metrics','shuffle_hashes'])
 assert new['config_sha256']==m['recovery_config_sha256']==hashlib.sha256((target/'config.json').read_bytes()).hexdigest()
 assert finite(new)
 before=steps(old);after=steps(new);assert len(before)==len(after)
 difference=[b-a for a,b in zip(before,after)];assert min(difference)>=0
 changed=any(not torch.equal(a,b) for a,b in zip(tensors(old['current']),tensors(new['current'])))
 if count>n:assert min(difference)>0 and changed
 rows.append({'run':rid,'source_epochs':n,'current_saved_epochs':count,'added_complete_epochs':count-n,
              'minimum_added_optimizer_steps':min(difference),'current_parameters_differ':changed,
              'current_checkpoint_sha256':hashlib.sha256(raw).hexdigest(),'checkpoint_bytes':len(raw),
              'all_source_histories_preserved':True,'all_saved_tensors_finite':True,
              'configuration_binding_verified':True,'source_files_unchanged':True,
              'failure_exists_in_recovery':(target/'failure.json').exists()})
 del old,new,raw
queries=[]
for cmd in [['scontrol','show','job','-o',str(jobs[prep['case']])],['sacct','-n','-X','-j',str(jobs[prep['case']]),'--format=JobID,State,ExitCode,NodeList','-P']]:
 r=subprocess.run(cmd,capture_output=True,text=True,timeout=30);queries.append({'command':cmd,'returncode':r.returncode,'stdout':r.stdout,'stderr':r.stderr})
print(json.dumps({'status':'read_only_formal_gradient_resume_checkpoint_audit',
 'checked_at_beijing':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
 'case':prep['case'],'job_id':jobs[prep['case']],'root':str(root),'members':rows,
 'additional_complete_member_epochs':sum(x['added_complete_epochs'] for x in rows),
 'any_new_failure_file':any(x['failure_exists_in_recovery'] for x in rows),
 'scheduler_queries':queries,'training_or_checkpoint_files_written':False,'evaluation_values_read':False},sort_keys=True))
PY

python3 - <<'PY'
import datetime,json,subprocess
nodes=['ngu001','ngu004','ngu005','ngu006','ngu007','ngu008','ngu010']
r=subprocess.run(['scontrol','show','node','-o',','.join(nodes)],capture_output=True,text=True,timeout=30)
print(json.dumps({'status':'read_only_eligible_partition_node_allocation','checked_at_beijing':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),'command':r.args,'returncode':r.returncode,'stdout':r.stdout,'stderr':r.stderr,'scheduler_mutated':False,'evaluation_values_read':False}))
PY
