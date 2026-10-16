#!/usr/bin/env bash
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
python -B - <<'PY'
import ast,contextlib,datetime,hashlib,io,json,pathlib,re,runpy,subprocess
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_training_covariance_failure_006_3090_A40_20261016_003')
job=str(json.loads((root/'records/scheduler_jobs.json').read_bytes())['covariance_diagnostic'])
ctl='/usr/local/globle/softs/slurm/19.05.4.1/bin/scontrol'
def sha(b):return hashlib.sha256(b).hexdigest()
def q(c):
 p=subprocess.run(c,capture_output=True,text=True,timeout=30);return dict(command=c,returncode=p.returncode,stdout=p.stdout,stderr=p.stderr)
def save(p,v):
 with p.open('x',encoding='utf-8') as f:json.dump(v,f,sort_keys=True,indent=2);f.write('\n')
entry=root/'hpc/replay_validation_covariance_diagnostic.py';original=entry.read_bytes()
assert sha(original)=='6c69f7b7dca69a0233624d3c9cb2a3e831b27c67007a58f65dd2d1ce7de81a53'
assert sha((root/'package_manifest.json').read_bytes())=='883731fec6a2ac513e8967f4aadcdd6bded89faa761f05257add2b32b5e65bd6'
old="require({k for k in config['effective_config'] if config['effective_config'][k]!=runtime_config['effective_config'][k]}=={'device_identity'}, 'non-hardware config changed')"
new="require({k for k in config['effective_config'] if config['effective_config'][k]!=runtime_config['effective_config'][k]}<={'device_identity'}, 'non-hardware config changed')"
text=original.decode();assert text.count(old)==1;repaired=text.replace(old,new).encode()
a,b=ast.parse(original),ast.parse(repaired)
old_nodes={n.name:ast.dump(n,include_attributes=False) for n in a.body if isinstance(n,(ast.ClassDef,ast.FunctionDef)) and n.name!='execute'}
new_nodes={n.name:ast.dump(n,include_attributes=False) for n in b.body if isinstance(n,(ast.ClassDef,ast.FunctionDef)) and n.name!='execute'}
assert old_nodes==new_nodes
record=dict(status='dual_entry_metadata_preflight',job_id=job,root=str(root),source_job='243692',
 before_entry_sha256=sha(original),after_entry_sha256=sha(repaired),scientific_source_files_changed=False,
 numerical_assertions_changed=False,training_or_optimizer_operations=False,submissions=0,cancellations=0,
 reason='Allow zero hardware metadata differences for an original3090; reject every nonhardware effective_config change.',
 checked_at_beijing=datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat())
record['queue_before']=q(['squeue','-h','-j',job,'-o','%i|%T|%Z']);assert record['queue_before']['returncode']==0
rows=[x.split('|') for x in record['queue_before']['stdout'].splitlines() if x.strip()]
if rows and rows==[[job,'PENDING',str(root)]] and not (root/'evidence').exists():
 record['native_before']=q([ctl,'show','job','-o',job]);assert record['native_before']['returncode']==0
 f=dict(re.findall(r'(\w+)=([^\s]+)',record['native_before']['stdout']))
 assert f['JobState']=='PENDING' and f['UserId']=='sunyiq(2272)' and f['WorkDir']==str(root) and f['RunTime']=='00:00:00'
 attempt=root/'records/queued_entry_repair_attempt.json';save(attempt,record)
 print(json.dumps(record,sort_keys=True),flush=True)
 record['hold_response']=q([ctl,'hold',job]);assert record['hold_response']['returncode']==0,record
 record['held_state']=q([ctl,'show','job','-o',job]);f=dict(re.findall(r'(\w+)=([^\s]+)',record['held_state']['stdout']))
 assert f['JobState']=='PENDING' and f['Reason']=='JobHeldUser' and f['RunTime']=='00:00:00'
 assert not (root/'evidence').exists() and entry.read_bytes()==original
 archive=root/'records/queued_entry_repair';archive.mkdir(exist_ok=False)
 (archive/'original_observer.py').open('xb').write(original)
 manifest=root/'package_manifest.json';manifest_bytes=manifest.read_bytes();(archive/'original_package_manifest.json').open('xb').write(manifest_bytes)
 v2=root/'hpc/replay_validation_covariance_diagnostic_v2.py';v2.open('xb').write(repaired)
 tmp=entry.with_name(entry.name+'.metadata_v2.tmp');tmp.open('xb').write(repaired);tmp.replace(entry)
 values=json.loads(manifest_bytes);values['files'][entry.relative_to(root).as_posix()]={'sha256':sha(repaired),'bytes':len(repaired)}
 values['files'][v2.relative_to(root).as_posix()]={'sha256':sha(repaired),'bytes':len(repaired)}
 values['operational_entry_revision']={'old_manifest_sha256':sha(manifest_bytes),'original_entry_sha256':sha(original),'reason':record['reason'],'numerical_source_files_changed':False}
 tmp=manifest.with_name(manifest.name+'.metadata_v2.tmp');save(tmp,values);tmp.replace(manifest)
 record['current_runtime_package_manifest_sha256']=sha(manifest.read_bytes())
 record['release_response']=q([ctl,'release',job]);assert record['release_response']['returncode']==0,record
 record['native_after']=q([ctl,'show','job','-o',job]);record['status']='queued_dual_metadata_entry_repaired_same_job_released'
 record['priority_may_be_recalculated_by_native_hold_release']=True
else:
 record['status']='entry_metadata_repair_not_applied_job_already_active_or_terminal'
save(root/'records/queued_entry_metadata_repair.json',record)
stream=io.StringIO()
with contextlib.redirect_stdout(stream):runpy.run_path(str(root/'hpc/probe_covariance_diagnostic.py'),run_name='__main__')
probe=json.loads(stream.getvalue());probe['queued_entry_metadata_repair']=record
print(json.dumps(probe,sort_keys=True),flush=True)
PY
