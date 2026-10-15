#!/usr/bin/env bash
# Retire only the authenticated diagnostic with an invalid identity assertion.
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
python -B - <<'PY'
import datetime, hashlib, json, pathlib, subprocess, time
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_validation_joseph_factorization_audit_20261016_001')
inbox=pathlib.Path('inbox/zhenjiang-six-source-four-target-ukf')
assert int((inbox/'seq').read_text())==501
def read(p):return json.loads(p.read_bytes())
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def query(args):
 p=subprocess.run(args,capture_output=True,text=True,timeout=30)
 assert p.returncode==0,{'args':args,'stdout':p.stdout,'stderr':p.stderr}
 return {'command':args,'returncode':p.returncode,'stdout':p.stdout,'stderr':p.stderr}
def write(p,v):
 with p.open('x',encoding='utf-8') as f:json.dump(v,f,sort_keys=True);f.write('\n')
assert read(root/'records/scheduler_jobs.json')=={'covariance_diagnostic':'243308'}
assert sha(root/'diagnostic_spec.json')=='5c8e342fdae3a685559b2d2ddcc4847cab77b531088a4ab1aec7a5e7d9463f9e'
manifest=read(root/'package_manifest.json')
main=root/'hpc/audit_saved_joseph_factors.py'
assert sha(main)==manifest['files']['hpc/audit_saved_joseph_factors.py']['sha256']
assert 'assert torch.equal(original[index:index+1], candidate)' in main.read_text()
source=pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261015_recovery_005')
run=source/'runs/explicit_gru__historical_capacity__tune_branch__filter_joint__s101__lr0p003'
assert sha(run/'continuation.pt')=='fa1993331b1ae4c35328ba7c3c928045452f0d4755ac35461450f287720f9589'
before=query(['squeue','-h','-u','sunyiq','-o','%i|%j|%T|%Z'])
rows=[line.split('|') for line in before['stdout'].splitlines() if line.startswith('243308|')]
assert len(rows)<=1
if rows:assert rows[0][1]=='zj_gru_joseph_factor_diag_261016_001' and rows[0][3]==str(root)
response=None
if rows and rows[0][2]=='PENDING':
 request=root/'records/controller_assertion_cancellation_request_501.json'
 write(request,{'job_id':'243308','workdir':str(root),'original_queue_row':rows[0],
                'reason':'unjustified original-versus-candidate equality assertion',
                'maximum_cancellation_attempts':1,'maximum_submission_attempts':0})
 p=subprocess.run(['scancel','243308'],capture_output=True,text=True,timeout=30)
 response={'returncode':p.returncode,'stdout':p.stdout,'stderr':p.stderr}
 write(root/'records/controller_assertion_cancellation_response_501.json',response)
 assert p.returncode==0,'uncertain cancellation requires read-only reconciliation, never repeat'
accounting=None;live=None
for attempt in range(4):
 live=query(['squeue','-h','-u','sunyiq','-o','%i|%j|%T|%Z'])
 accounting=query(['sacct','-n','-X','-j','243308','--format=JobID,State,ExitCode,Start,End,NodeList','-P'])
 own=[line for line in live['stdout'].splitlines() if line.startswith('243308|')]
 final=[line.split('|') for line in accounting['stdout'].splitlines() if line.startswith('243308|')]
 if not own and len(final)==1 and final[0][1].split()[0] not in ('PENDING','RUNNING'):break
 if attempt<3:time.sleep(2)
unchanged=sha(run/'continuation.pt')=='fa1993331b1ae4c35328ba7c3c928045452f0d4755ac35461450f287720f9589'
assert unchanged
record={'status':'bad_joseph_factor_entry_reconciled','checked_at_beijing':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
 'job_id':'243308','diagnostic_root':str(root),'before_queue':before,'after_queue':live,'actual_accounting':accounting,
 'cancellation_response':response,'cancellation_attempts':int(response is not None),'new_jobs_submitted':0,
 'source_checkpoint_unchanged':True,'formal_epochs_added':0,'scientific_rules_changed':False,'evaluation_values_read':False,
 'matching_job_inactive':not own,'actual_terminal_accounting_available':not own and len(final)==1 and final[0][1].split()[0] not in ('PENDING','RUNNING')}
write(root/'records/controller_assertion_reconciliation_501.json',record)
print(json.dumps(record,sort_keys=True))
PY
