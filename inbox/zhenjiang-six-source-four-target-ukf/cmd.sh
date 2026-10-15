#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
"""Lightweight allocation/checkpoint watch; no source changes or GPU jobs."""
import datetime,hashlib,json,pathlib,re,subprocess
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261015_recovery_005')
case='explicit_gru__historical_capacity'
job=str(json.loads((root/'records/scheduler_jobs.json').read_text())[case])
def query(c):
    p=subprocess.run(c,capture_output=True,text=True,timeout=30)
    return {'command':c,'returncode':p.returncode,'stdout':p.stdout,'stderr':p.stderr}
members={}
for folder in sorted(root.joinpath('runs').glob('*__tune_branch__*')):
    metric=folder/'metrics.json';point=folder/'continuation.pt'
    prefix=metric.open('rb').read(131072).decode('utf-8')
    m=re.search(r'"validation_mae_cm"\s*:\s*',prefix)
    values=json.JSONDecoder().raw_decode(prefix[m.end():])[0]
    stat=point.stat()
    members[folder.name]={'completed_epochs':len(values),'history_sha256':hashlib.sha256(json.dumps(values,separators=(',',':')).encode()).hexdigest(),'continuation_bytes':stat.st_size,'continuation_mtime_ns':stat.st_mtime_ns,'failure_exists':folder.joinpath('failure.json').exists()}
queries=[query(['squeue','-h','-u','sunyiq','-o','%i|%T|%Z|%e|%l|%P|%C|%b|%N']),query(['sacct','-n','-X','-j',job,'--format=JobID,State,ExitCode,Elapsed,NodeList,Reason','-P'])]
record={'status':'read_only_recovery_queue_light_probe','checked_at_beijing':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),'root':str(root),'case':case,'job_id':job,'queries':queries,'members':members,'formal_complete_exists':root.joinpath('records',case,'training_complete.json').exists(),'scientific_configuration_changed':False,'evaluation_values_read':False,'checkpoints_loaded':False}
for n in ('recovery_backfill_adjustment_20261012.response.json','gpu_binding_'+job+'.json','gpu_acceptance_'+job+'.json'):
    p=root/'records'/n
    if p.exists():record[n]=json.loads(p.read_text())
for p in root.joinpath('logs').glob('*_'+job+'.out'):
    with p.open('rb') as f:f.seek(max(0,p.stat().st_size-12000));record['log_tail']=f.read().decode('utf-8',errors='replace')
columns=['JobID','State','ExitCode','Start','End','Elapsed','Timelimit','NodeList','AllocTRES']
terminal=query(['sacct','-n','-X','-j',job,'--format='+','.join(columns),'-P'])
record['queries'].append(terminal)
if terminal['returncode']==0:
    line=next((line for line in terminal['stdout'].splitlines() if line.startswith(job+'|')),None)
    if line:
        fields=dict(zip(columns,line.split('|')))
        if fields['State'].split()[0] in ('FAILED','COMPLETED','TIMEOUT','CANCELLED'):
            record['terminal_accounting_fields']=fields
record['failure_records']={}
for rid in record['members']:
    p=root/'runs'/rid/'failure.json'
    if p.exists():record['failure_records'][rid]=json.loads(p.read_text())
critical=root/'runs'/('explicit_gru__historical_capacity__tune_branch__filter_joint__s101__lr0p003')
record['failure_artifact_inventory']=[{'name':p.name,'bytes':p.stat().st_size,'mtime_ns':p.stat().st_mtime_ns} for p in sorted(critical.iterdir()) if p.is_file()]
print(json.dumps(record,sort_keys=True))
PY

python3 -B /data1/home/sunyiq/zhenjiang_validation_covariance_diagnostic_20261015_001/hpc/probe_covariance_diagnostic.py

python3 -B /data1/home/sunyiq/zhenjiang_validation_sigma_gpu_audit_20261015_001/hpc/probe_covariance_diagnostic.py

python3 -B /data1/home/sunyiq/zhenjiang_validation_cholesky_guard_diagnostic_20261015_001/hpc/probe_covariance_diagnostic.py

python3 -B /data1/home/sunyiq/zhenjiang_validation_posterior_diagnostic_20261015_001/hpc/probe_covariance_diagnostic.py

python3 -B /data1/home/sunyiq/zhenjiang_validation_joseph_compensation_20261015_001/hpc/probe_covariance_diagnostic.py

python3 -B /data1/home/sunyiq/zhenjiang_validation_joseph_failure_diagnostic_20261015_001/hpc/probe_covariance_diagnostic.py

python -B /data1/home/sunyiq/zhenjiang_validation_joseph_factorization_audit_20261016_002/hpc/probe_covariance_diagnostic.py

python3 -B /data1/home/sunyiq/zhenjiang_validation_joseph_compensated_factor_20261016_001/hpc/probe_covariance_diagnostic.py
