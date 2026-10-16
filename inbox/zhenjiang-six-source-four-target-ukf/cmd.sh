#!/usr/bin/env bash
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
python -B - <<'PY'
import datetime,hashlib,io,json,pathlib,tarfile
inbox=pathlib.Path('inbox/zhenjiang-six-source-four-target-ukf');sequence=int((inbox/'seq').read_text());assert sequence==556
raw=(inbox/f'payload_complete_comparison_20261006_{sequence}.tar.gz').read_bytes();assert hashlib.sha256(raw).hexdigest()=='b549ea9a1eaad557e3ec807535e314dbf08a3d98575f5ee5d9ed9e1ff5c26079'
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_training_covariance_failure_006_A40_20261016_002');assert not root.exists(),'existing isolated deployment requires read-only reconciliation, never overwrite or repeat'
with tarfile.open(fileobj=io.BytesIO(raw),mode='r:gz') as archive:
 members=archive.getmembers();assert members and all(m.isfile() for m in members);assert len(members)==17
 for m in members:
  relative=pathlib.PurePosixPath(m.name);assert not relative.is_absolute() and '..' not in relative.parts and root in (root/m.name).resolve().parents
 content={m.name:archive.extractfile(m).read() for m in members}
manifest=json.loads(content['package_manifest.json']);assert set(content)==set(manifest['files'])|{'package_manifest.json'}
for name,item in manifest['files'].items():assert len(content[name])==item['bytes'] and hashlib.sha256(content[name]).hexdigest()==item['sha256']
spec=json.loads(content['diagnostic_spec.json']);assert spec['schema']=='isolated_failed006_original_training_epoch47_v1'
assert spec['source_job']=='243692' and spec['source_code_hash']=='4232fbb467341b6332f91e9289cdb975613babb5d29e2079b66d55f7822c3757'
assert spec['expected_saved_epoch']==46 and spec['replayed_epoch']==47 and spec['old_diagnostic_half_epoch_state_used'] is False
assert spec['selection_years']==[2021] and spec['training_years']==[2017,2018,2019,2020] and spec['maximum_replay_epochs']==1
assert spec['formal_checkpoint_write_allowed'] is False and spec['evaluation_values_read'] is False and spec['scientific_rules_changed'] is False
assert spec['hardware_binding_changed_by_explicit_human_authority'] is True
assert spec['hardware_authority']['answer']=='允许转用A40，保持原数值与训练规则'
source=pathlib.Path(spec['source_root'])
for rid,files in spec['all_member_source_files'].items():
 for name,item in files.items():
  p=source/'runs'/rid/name;b=p.read_bytes();assert len(b)==item['bytes'] and hashlib.sha256(b).hexdigest()==item['sha256']
for name,expected in spec['source_code_file_hashes'].items():assert hashlib.sha256((source/name).read_bytes()).hexdigest()==expected
root.mkdir(exist_ok=False)
for name,b in content.items():
 p=root/name;p.parent.mkdir(parents=True,exist_ok=True)
 with p.open('xb') as f:f.write(b)
for name in ['records','logs']:(root/name).mkdir(exist_ok=True)
print(json.dumps({'status':'joseph_failure_replay_diagnostic_deployed','checked_at_beijing':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),'diagnostic_root':str(root),'source_failed_job':'243692','payload_sha256':hashlib.sha256(raw).hexdigest(),'manifest_sha256':hashlib.sha256(content['package_manifest.json']).hexdigest(),'formal_training_restarted':False,'formal_epochs_added':0,'evaluation_values_read':False},sort_keys=True))
PY
python -B - <<'PY'

import datetime,json,pathlib,re,subprocess,sys,time
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_training_covariance_failure_006_A40_20261016_002');old=pathlib.Path('/data1/home/sunyiq/zhenjiang_training_covariance_failure_006_20261016_001');job='244010'
control='/usr/local/globle/softs/slurm/19.05.4.1/bin/scontrol';cancel='/usr/local/globle/softs/slurm/19.05.4.1/bin/scancel'
def q(c):
 p=subprocess.run(c,capture_output=True,text=True,timeout=30);return {'command':c,'returncode':p.returncode,'stdout':p.stdout,'stderr':p.stderr}
def save(name,v):
 with (root/'records'/name).open('x',encoding='utf-8') as f:json.dump(v,f,sort_keys=True,indent=2);f.write('\n')
a={'status':'authorized_A40_pending_replacement_preflight','at_beijing':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),'old_job':job,'old_root':str(old),'new_root':str(root),'new_submissions_maximum':1,'old_pending_cancellations_maximum':1,'other_jobs_modified':False,'formal_epochs_added':0}
assert json.loads((root/'hardware_authority.json').read_bytes())['answer']=='允许转用A40，保持原数值与训练规则'
assert json.loads((old/'records/scheduler_jobs.json').read_bytes())=={'covariance_diagnostic':job}
a['other_three_before']=q(['squeue','-h','-j','236706,236707,237928','-o','%i|%T|%Z|%l|%C|%b'])
a['queue_before']=q(['squeue','-h','-u','sunyiq','-o','%i|%j|%T|%Z']);assert a['queue_before']['returncode']==0
rows=[x.split('|') for x in a['queue_before']['stdout'].splitlines() if x.startswith(job+'|')];assert len(rows)<=1
if rows and rows[0][2]!='PENDING':
 a.update(status='A40_prepared_original_replay_active_no_cancel_no_submission',actual_old_state=rows[0][2]);save('old_pending_replacement_deferred.json',a);print(json.dumps(a,sort_keys=True),flush=True)
 subprocess.run([sys.executable,'-B',str(old/'hpc/probe_covariance_diagnostic.py')],check=True)
else:
 assert not (root/'records/old_pending_cancel_attempt.json').exists()
 if rows:
  a['native_before']=q([control,'show','job','-o',job]);assert a['native_before']['returncode']==0
  f=dict(re.findall(r'(\w+)=([^\s]+)',a['native_before']['stdout']))
  assert f['JobId']==job and f['JobState']=='PENDING' and f['UserId']=='sunyiq(2272)' and f['WorkDir']==str(old) and f['Command']==str(old/'hpc/covariance_diagnostic.slurm')
  assert f['NodeList']=='(null)' and f['RunTime']=='00:00:00'
  save('old_pending_cancel_attempt.json',a)
  a['cancel_response']=q([cancel,'--state=PENDING',job]);save('old_pending_cancel_response.json',a)
  assert a['cancel_response']['returncode']==0,'cancel uncertain; never blindly repeat'
  for _ in range(20):
   check=q(['squeue','-h','-u','sunyiq','-o','%i|%T|%Z']);assert check['returncode']==0
   if not any(line.startswith(job+'|') for line in check['stdout'].splitlines()):break
   time.sleep(1)
  else:raise RuntimeError('old job still active; no new submission')
 a['old_final_accounting']=q(['sacct','-n','-X','-j',job,'--format=JobID,State,ExitCode,Start,End,NodeList','-P'])
 assert a['old_final_accounting']['returncode']==0
 a.update(status='authorized_A40_old_pending_replaced_no_original_training_cancelled',old_job_was_pending=bool(rows),new_submission_not_yet_called=True)
 save('old_pending_replacement_audit.json',a);print(json.dumps(a,sort_keys=True),flush=True)
 p=subprocess.run([sys.executable,'-B',str(root/'hpc/submit_covariance_diagnostic.py')]);assert p.returncode==0
 a['other_three_after']=q(['squeue','-h','-j','236706,236707,237928','-o','%i|%T|%Z|%l|%C|%b'])
 save('other_three_after_authorized_replacement.json',a)
 subprocess.run([sys.executable,'-B',str(root/'hpc/probe_covariance_diagnostic.py')],check=True)
PY
