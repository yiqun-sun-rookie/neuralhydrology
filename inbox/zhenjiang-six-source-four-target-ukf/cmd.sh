#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
import datetime, hashlib, json, pathlib, subprocess, concurrent.futures
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261012_recovery_003')
case='explicit_gru__historical_capacity'
job=str(json.loads((root/'records/scheduler_jobs.json').read_text())[case])
diagnostic=pathlib.Path('/data1/home/sunyiq/zhenjiang_gradient_diagnostic_20261011_001')
def query(command):
    try:
        r=subprocess.run(command,capture_output=True,text=True,timeout=25)
        return {'command':command,'returncode':r.returncode,'stdout':r.stdout,'stderr':r.stderr}
    except Exception as e:return {'command':command,'error':str(e)}
commands=[['scontrol','show','job','-dd',job],['scontrol','show','partition','hgpu2p'],
          ['scontrol','show','config'],['sinfo','-h','-p','hgpu2p','-N','-o','%N|%T|%G|%C|%f'],
          ['squeue','-h','-p','hgpu2p','-o','%i|%u|%T|%N|%b|%l|%e|%Q|%R'],
          ['scontrol','show','node','-d','ngu001,ngu004,ngu005,ngu006,ngu007,ngu008,ngu010'],
          ['scontrol','show','reservation','-o']]
results=[]
for c in commands:
    r=query(c)
    if c==['scontrol','show','config']:
        r['stdout']='\n'.join(l for l in r.get('stdout','').splitlines() if any(w in l for w in ('Scheduler','SelectType','Priority','KillWait','OverTimeLimit','Preempt','SlurmctldVersion','SlurmctldDebug','GresTypes','AccountingStorageEnforce')))
    results.append(r)
gpu_command=['ssh','-o','BatchMode=yes','-o','ConnectTimeout=5','NODE','nvidia-smi --query-gpu=index,name,memory.total,memory.used,utilization.gpu --format=csv,noheader,nounits']
def node_query(n):
    c=list(gpu_command);c[5]=n;return query(c)
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    gpu=list(pool.map(node_query,['ngu001','ngu004','ngu005','ngu006','ngu007','ngu008','ngu010']))
records={}
for p in sorted(diagnostic.joinpath('records').glob('*.json')):
    if p.name in ('scheduler_jobs.json','submission_response.json','submission_attempt.json','diagnostic_job.json','diagnostic_submission_response.json','diagnostic_submission_attempt.json'):
        records[p.name]=json.loads(p.read_text())
report={'status':'read_only_backfill_options','checked_at_beijing':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),'root':str(root),'job_id':job,'queries':results,'eligible_node_gpu_queries':gpu,'diagnostic_registration':records,'script_sha256':hashlib.sha256((root/'hpc/pathfix_gradient_recovery_003.slurm').read_bytes()).hexdigest(),'script_text':(root/'hpc/pathfix_gradient_recovery_003.slurm').read_text(),'science_or_jobs_modified':False}
print(json.dumps(report,sort_keys=True))
PY
