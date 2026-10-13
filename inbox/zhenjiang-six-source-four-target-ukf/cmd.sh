#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
"""Lightweight allocation/checkpoint watch; no source changes or GPU jobs."""
import datetime,hashlib,json,pathlib,re,subprocess
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261012_recovery_003')
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
queries=[query(['scontrol','show','job','-o',job]),query(['sacct','-n','-X','-j',job,'--format=JobID,State,ExitCode,Elapsed,NodeList,Reason','-P'])]
record={'status':'read_only_recovery_queue_light_probe','checked_at_beijing':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),'root':str(root),'case':case,'job_id':job,'queries':queries,'members':members,'formal_complete_exists':root.joinpath('records',case,'training_complete.json').exists(),'scientific_configuration_changed':False,'evaluation_values_read':False,'checkpoints_loaded':False}
for n in ('recovery_backfill_adjustment_20261012.response.json','gpu_binding_'+job+'.json','gpu_acceptance_'+job+'.json'):
    p=root/'records'/n
    if p.exists():record[n]=json.loads(p.read_text())
for p in root.joinpath('logs').glob('*_'+job+'.out'):
    with p.open('rb') as f:f.seek(max(0,p.stat().st_size-12000));record['log_tail']=f.read().decode('utf-8',errors='replace')
print(json.dumps(record,sort_keys=True))
PY
