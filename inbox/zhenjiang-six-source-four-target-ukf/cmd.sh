#!/usr/bin/env bash
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
python -B - <<'PY'
import hashlib,io,json,pathlib,subprocess,tarfile,sys
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261012_recovery_003')
payload=pathlib.Path('inbox/zhenjiang-six-source-four-target-ukf/payload_complete_comparison_20261006_249.tar.gz')
raw=payload.read_bytes();assert hashlib.sha256(raw).hexdigest()=='d5161afa66544c1bb77ff65e3e63aeeb85545f486e32909dcc5d022f47c2b6af'
with tarfile.open(fileobj=io.BytesIO(raw),mode='r:gz') as t:
 members=t.getmembers();assert {m.name for m in members}=={'hpc/run_scheduler_slice.py','hpc/submit_scheduler_continuation.py','slice_support_manifest.json'} and len(members)==3
 assert all(m.isfile() for m in members)
 content={m.name:t.extractfile(m).read() for m in members}
manifest=json.loads(content.pop('slice_support_manifest.json'))
assert set(content)==set(manifest['files'])
for name,b in content.items():assert hashlib.sha256(b).hexdigest()==manifest['files'][name]['sha256'] and len(b)==manifest['files'][name]['bytes']
sys.path.insert(0,str(root));from src.scheduler import code_identity
assert code_identity()==manifest['code_hash']
auth=json.loads(root.joinpath('records/authorization.json').read_text());assert auth['code_hash']==code_identity() and auth['authority']['technical_recovery']
for name,b in content.items():
 p=root/name
 assert not p.exists(),'preserve existing scheduler support; inspect before another deployment'
 with p.open('xb') as f:f.write(b)
with root.joinpath('records/scheduler_slice_support_20261012.json').open('x') as f:json.dump(manifest,f,indent=2,sort_keys=True);f.write('\n')
assert code_identity()==manifest['code_hash']
print(json.dumps({'status':'scheduler_slice_support_deployed_no_job_submitted','root':str(root),'manifest':manifest,'job_id':json.loads(root.joinpath('records/scheduler_jobs.json').read_text())['explicit_gru__historical_capacity'],'training_code_identity_unchanged':True}),flush=True)
for command in [['sacctmgr','-n','-P','show','association','where','user=sunyiq','format=Account,User,Partition,QOS,DefaultQOS'],['scontrol','show','job','-o',str(json.loads(root.joinpath('records/scheduler_jobs.json').read_text())['explicit_gru__historical_capacity'])]]:
 p=subprocess.run(command,capture_output=True,text=True,timeout=30);print(json.dumps({'command':command,'returncode':p.returncode,'stdout':p.stdout,'stderr':p.stderr}),flush=True)
PY
