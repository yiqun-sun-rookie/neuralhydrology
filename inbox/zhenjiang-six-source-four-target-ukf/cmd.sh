#!/usr/bin/env bash
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
python -B - <<'PY'
import datetime,hashlib,io,json,pathlib,tarfile
inbox=pathlib.Path('inbox/zhenjiang-six-source-four-target-ukf');sequence=int((inbox/'seq').read_text());assert sequence==563
raw=(inbox/f'payload_complete_comparison_20261006_{sequence}.tar.gz').read_bytes();assert hashlib.sha256(raw).hexdigest()=='9bc461c6c26e04985832026a97dad0cc540b9bd14dd59ce3a949b40c9fbfa91a'
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_training_covariance_failure_006_guarded_20261016_004');assert not root.exists(),'existing isolated deployment requires read-only reconciliation, never overwrite or repeat'
with tarfile.open(fileobj=io.BytesIO(raw),mode='r:gz') as archive:
 members=archive.getmembers();assert members and all(m.isfile() for m in members);assert len(members)==18
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
import subprocess
def query(c):
 p=subprocess.run(c,capture_output=True,text=True,timeout=30);assert p.returncode==0,(c,p.stdout,p.stderr);return p.stdout
oldjob='244105'
rows=[x.split('|') for x in query(['sacct','-n','-X','-j',oldjob,'--format=JobID,State,ExitCode,Start,End,NodeList','-P']).splitlines() if x.startswith(oldjob+'|')]
assert len(rows)==1 and rows[0][:6]==[oldjob,'FAILED','1:0','2026-10-16T23:29:20','2026-10-16T23:29:33','ngu009']
assert not any(x.startswith(oldjob+'|') for x in query(['squeue','-h','-u','sunyiq','-o','%i|%T|%Z']).splitlines())
prior=pathlib.Path('/data1/home/sunyiq/zhenjiang_training_covariance_failure_006_3090_A40_20261016_003')
assert hashlib.sha256((prior/'hpc/replay_validation_covariance_diagnostic.py').read_bytes()).hexdigest()=='af352bceaf126676d1ce77d3650e7029bbdf7e0845cdc0e192576448ceb5e6cf'
assert hashlib.sha256((prior/'package_manifest.json').read_bytes()).hexdigest()=='081c5e33eb18462b8ab5cb81647a9f426493ed117542d5e7eba2c45126a78b23'
assert not (prior/'evidence').exists(), 'a scientific replay ran; reconcile actual evidence before continuing'
root.mkdir(exist_ok=False)
for name,b in content.items():
 p=root/name;p.parent.mkdir(parents=True,exist_ok=True)
 with p.open('xb') as f:f.write(b)
for name in ['records','logs']:(root/name).mkdir(exist_ok=True)
print(json.dumps({'status':'joseph_failure_replay_diagnostic_deployed','checked_at_beijing':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),'diagnostic_root':str(root),'source_failed_job':'243692','payload_sha256':hashlib.sha256(raw).hexdigest(),'manifest_sha256':hashlib.sha256(content['package_manifest.json']).hexdigest(),'formal_training_restarted':False,'formal_epochs_added':0,'evaluation_values_read':False},sort_keys=True))
PY
python -B /data1/home/sunyiq/zhenjiang_training_covariance_failure_006_guarded_20261016_004/hpc/submit_covariance_diagnostic.py
python -B /data1/home/sunyiq/zhenjiang_training_covariance_failure_006_guarded_20261016_004/hpc/probe_covariance_diagnostic.py
