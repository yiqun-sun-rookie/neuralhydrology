#!/usr/bin/env bash
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
python -B - <<'PY'
import datetime,hashlib,io,json,pathlib,subprocess,tarfile
inbox=pathlib.Path('inbox/zhenjiang-six-source-four-target-ukf');sequence=int((inbox/'seq').read_text());assert sequence==448
raw=(inbox/f'payload_complete_comparison_20261006_{sequence}.tar.gz').read_bytes()
assert hashlib.sha256(raw).hexdigest()=='0e00ad5fee096a4e9b1f8d5a2f6d0da28924c786c7d8c80d96610fd56b174ee1'
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261015_recovery_004')
def read(p):return json.loads(p.read_bytes())
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
with tarfile.open(fileobj=io.BytesIO(raw),mode='r:gz') as t:
 members=t.getmembers();assert all(m.isfile() for m in members);assert len(members)==4
 content={m.name:t.extractfile(m).read() for m in members};assert len(content)==4
manifest_name='records/covariance_startup_runtime_repair_manifest_20261015.json';manifest=json.loads(content[manifest_name])
assert set(content)==set(manifest['files'])|{manifest_name}
assert set(manifest['files'])=={'hpc/prepare_recovery.py','hpc/submit_covariance_recovery_squeue_20261015_v2.py','records/covariance_startup_runtime_repair_admitted_20261015.json'}
assert manifest['science_rules_changed'] is False and manifest['scheduler_submissions']==0
for name,item in manifest['files'].items():assert len(content[name])==item['bytes'] and hashlib.sha256(content[name]).hexdigest()==item['sha256']
for name in content:assert not (root/name).exists(),'existing partial runtime repair requires read-only reconciliation'
admission=json.loads(content['records/covariance_startup_runtime_repair_admitted_20261015.json'])
assert admission['failed_job_id']=='242582' and admission['authenticated_receipt']['sha256']==manifest['source_receipt_sha256']
assert sha(pathlib.Path(admission['failed_log_path']))==admission['failed_log_sha256']
source=pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261012_recovery_003/hpc/prepare_recovery.py')
assert sha(source)==admission['helper_sha256']==hashlib.sha256(content['hpc/prepare_recovery.py']).hexdigest()
assert read(root/'records/scheduler_jobs.json')['explicit_gru__historical_capacity']=='242582'
audit=read(root/'records/covariance_checkpoint_audit_latest.json');assert sha(pathlib.Path(audit['immutable_record']))==audit['immutable_record_sha256']
assert str(audit['job_id'])=='242582' and audit['all_source_bytes_unchanged'] and not audit['any_new_failure_file']
assert audit['additional_complete_member_epochs']==0 and len(audit['members'])==12
assert {m['run']:m['current_checkpoint_sha256'] for m in audit['members']}==admission['baseline_checkpoint_sha256']
for m in audit['members']:assert sha(root/'runs'/m['run']/'continuation.pt')==m['current_checkpoint_sha256']
queries=[]
for c in [['squeue','-h','-u','sunyiq','-o','%i|%j|%T|%Z'],['sacct','-n','-X','-j','242582','--format=JobID,State,ExitCode,Start,End','-P']]:
 p=subprocess.run(c,capture_output=True,text=True,timeout=30);assert p.returncode==0;queries.append({'command':c,'stdout':p.stdout,'returncode':p.returncode})
rows=[l.split('|') for l in queries[0]['stdout'].splitlines() if l.strip()]
assert not any(r[1].startswith(('zj_gru_cov_','zj_gru_covariance_','zj_gru_gradient_recovery','zj_gru_slice_')) or r[3]==str(root) for r in rows)
acct=[l.split('|') for l in queries[1]['stdout'].splitlines() if l.startswith('242582|')]
assert len(acct)==1 and acct[0][1:3]==['FAILED','1:0'] and acct[0][3:5]==[admission['actual_start_time'],admission['actual_end_time']]
import sys
sys.path.insert(0,str(root))
from src.scheduler import code_identity
assert code_identity(root)==read(root/'records/authorization.json')['code_hash']==manifest['code_hash']
for name,b in content.items():
 p=root/name;assert root in p.resolve().parents
 with p.open('xb') as f:f.write(b)
assert code_identity(root)==manifest['code_hash']
print(json.dumps({'status':'covariance_missing_startup_helper_repaired','checked_at_beijing':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),'root':str(root),'failed_job_id':'242582','payload_sha256':hashlib.sha256(raw).hexdigest(),'helper_sha256':sha(root/'hpc/prepare_recovery.py'),'submitter_sha256':sha(root/'hpc/submit_covariance_recovery_squeue_20261015_v2.py'),'code_hash':manifest['code_hash'],'science_rules_changed':False,'training_submitted':False,'queries':queries},sort_keys=True))
PY
python -B /data1/home/sunyiq/zhenjiang_complete_comparison_20261015_recovery_004/hpc/audit_covariance_continuation_20261015.py
