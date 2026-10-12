#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
"""Offer backfill windows on the registered pending recovery, retaining queue age.

Only scheduling resources change. Full 200/400-epoch budgets, run identities,
complete epoch checkpoints, source failures and all other jobs are retained.
"""
import datetime,hashlib,json,os,pathlib,re,subprocess
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261012_recovery_003')
case='explicit_gru__historical_capacity'
job=str(json.loads((root/'records/scheduler_jobs.json').read_text())[case])
diag=pathlib.Path('/data1/home/sunyiq/zhenjiang_gradient_diagnostic_20261011_001')
diag_job=str(json.loads((diag/'records/scheduler_jobs.json').read_text())['gradient_diagnostic'])
def run(c):
    p=subprocess.run(c,capture_output=True,text=True,timeout=30)
    return {'command':c,'returncode':p.returncode,'stdout':p.stdout,'stderr':p.stderr}
def fields(r):
    assert r['returncode']==0,r
    return dict(re.findall(r'(\w+)=([^\s]+)',r['stdout']))
def save(p,d):
    with p.open('x',encoding='utf-8') as f:
        json.dump(d,f,sort_keys=True,indent=2);f.write('\n');f.flush();os.fsync(f.fileno())
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def now():return datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat()
script=root/'hpc/pathfix_gradient_recovery_003.slurm'
auth=json.loads((root/'records/authorization.json').read_text())
assert auth['code_hash']=='19bf9eb19614f62a329da1cac2f2ec377558ff7f72d32ac5f5d935f30415eca0'
assert digest(root/'configs/protocol-v3.json')==auth['protocol_sha256']
assert auth['authority']['technical_recovery'] and auth['authority']['formal_training']
configs=list(root.joinpath('runs').glob('*__tune_branch__*/config.json'))
assert len(configs)==12
assert all(json.loads(p.read_text())['effective_config']['scheduler_continuation'] is True for p in configs)
assert all(not p.parent.joinpath('failure.json').exists() and p.parent.joinpath('continuation.pt').exists() for p in configs)
identities={str(p):digest(p) for p in [root/'configs/protocol-v3.json',root/'records/authorization.json',root/'records/data_preparation_complete.json',script,*configs]}
before=run(['scontrol','show','job','-o',job]);b=fields(before)
expected={'JobId':job,'JobName':'zj_gru_gradient_recovery_261012_003','UserId':'sunyiq(2272)','Partition':'hgpu2p','NumCPUs':'4','NumTasks':'1','TresPerNode':'gpu:1','ExcNodeList':'ngu[002,011]','Dependency':'(null)','WorkDir':str(root),'Command':str(script)}
assert all(b.get(k)==v for k,v in expected.items()),b
queue=run(['squeue','-h','-u','sunyiq','-o','%i|%j|%T|%N'])
assert queue['returncode']==0 and sum(l.split('|')[1]==expected['JobName'] for l in queue['stdout'].splitlines())==1
healthy=[]
for other_root,other_case in [(pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261006_002'),'explicit_gru__small'),(pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261006_002'),'legacy_lstm__historical_capacity'),(pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261008_recovery_002'),'legacy_lstm__small')]:
    jid=str(json.loads((other_root/'records/scheduler_jobs.json').read_text())[other_case])
    q=run(['scontrol','show','job','-o',jid]);f=fields(q)
    assert f['JobState']=='RUNNING' and jid not in (job,diag_job)
    healthy.append({'case':other_case,'job_id':jid,'before':q})
sched=run(['scontrol','show','config']);assert sched['returncode']==0 and re.search(r'SchedulerType\s*=\s*sched/backfill',sched['stdout'])
record={'status':'pending_recovery_backfill_attempt_reserved','time':now(),'job_id':job,'before':before,'duplicate_guard':queue,'healthy_jobs_before':healthy,'identities':identities,'allocation_time_limit_minutes':720,'minimum_backfill_minutes':120,'full_training_budget_unchanged':True,'scientific_configuration_changed':False,'maximum_gpu_count':1,'new_job_submitted':False,'queue_age_retained':True,'incomplete_epoch_on_scheduler_timeout_is_replayed_from_last_atomic_complete_checkpoint':True,'automatic_success_claim_allowed':False,'user_instruction':'shorten queue without changing experimental design or affecting the other three training jobs'}
attempt=root/'records/recovery_backfill_adjustment_20261012.attempt.json'
assert not attempt.exists(),'prior attempt exists; inspect response and scheduler before any further action'
if b['JobState']!='PENDING':
    record['status']='recovery_already_started_no_scheduling_change'
else:
    assert b['RunTime']=='00:00:00' and b['NodeList']=='(null)' and b['TimeLimit']=='UNLIMITED'
    save(attempt,record)
    record['update']=run(['scontrol','update','JobId='+job,'TimeLimit=12:00:00','TimeMin=02:00:00'])
    record['after']=run(['scontrol','show','job','-o',job]);a=fields(record['after'])
    record['status']='existing_recovery_backfill_window_verified' if record['update']['returncode']==0 and a.get('TimeLimit')=='12:00:00' and a.get('TimeMin')=='02:00:00' else 'scheduler_adjustment_requires_read_only_verification'
    assert all(a.get(k)==v for k,v in expected.items())
    assert a['SubmitTime']==b['SubmitTime'] and a['EligibleTime']==b['EligibleTime']
    assert all(digest(pathlib.Path(p))==v for p,v in identities.items())
    # The old isolated diagnostic has been superseded by an authenticated full
    # local epoch replay and the deployed repair. Cancel it only while pending.
    d_before=run(['scontrol','show','job','-o',diag_job]);d=fields(d_before)
    spec=json.loads((diag/'diagnostic_spec.json').read_text())
    assert spec['case']==case and spec['replayed_epoch']==41 and spec['formal_checkpoint_write_allowed'] is False
    assert d['JobName']==spec['job_name'] and d['WorkDir']==str(diag) and d['UserId']=='sunyiq(2272)'
    cancellation={'before':d_before,'diagnostic_only':True,'source_spec_sha256':digest(diag/'diagnostic_spec.json'),'reason':'isolated old diagnostic superseded by preserved local fault localization, full epoch replay and authenticated formal repair; preserve all its files'}
    if d['JobState']=='PENDING' and d['RunTime']=='00:00:00' and d['NodeList']=='(null)' and record['status']=='existing_recovery_backfill_window_verified':
        cancellation['action']=run(['scancel',diag_job]);cancellation['after']=run(['sacct','-n','-X','-j',diag_job,'--format=JobID,State,ExitCode','-P'])
        cancellation['status']='pending_obsolete_diagnostic_cancellation_requested'
    else:cancellation['status']='diagnostic_started_or_adjustment_unconfirmed_no_cancellation'
    record['obsolete_diagnostic']=cancellation
    record['healthy_jobs_after']=[]
    for row in healthy:
        q=run(['scontrol','show','job','-o',row['job_id']]);f=fields(q);old=fields(row['before'])
        for key in ('JobId','JobName','Command','WorkDir','NodeList','TimeLimit','TimeMin','SubmitTime','StartTime','NumCPUs','TresPerNode','JobState'):
            assert f[key]==old[key],(key,row['job_id'])
        record['healthy_jobs_after'].append({'case':row['case'],'job_id':row['job_id'],'after':q})
    record['healthy_jobs_unchanged']=True;record['finished_at_beijing']=now()
    save(root/'records/recovery_backfill_adjustment_20261012.response.json',record)
print(json.dumps(record,sort_keys=True))
PY
