#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
import datetime,hashlib,json,pathlib,subprocess
ROOT=pathlib.Path('/data1/home/sunyiq/zhenjiang_gradient_diagnostic_20261011_001')
report={'status':'read_only_isolated_gradient_diagnostic_status','root':str(ROOT),'checked_at_beijing':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),'training_inputs_read':False,'checkpoints_loaded':False,'evaluation_values_read':False,'formal_training_recovery_confirmed':False}
def record(p,whole=True):
    if not p.exists():return {'path':str(p),'exists':False}
    st=p.stat();d={'path':str(p),'exists':True,'bytes':st.st_size,'mtime_ns':st.st_mtime_ns}
    if whole:
        raw=p.read_bytes();d['sha256']=hashlib.sha256(raw).hexdigest();d['value']=json.loads(raw)
    return d
def query(args):
    p=subprocess.run(args,capture_output=True,text=True,timeout=30)
    return {'command':args,'returncode':p.returncode,'stdout':p.stdout,'stderr':p.stderr}
for name in ['diagnostic_spec.json','release_manifest.json','records/diagnostic_submission_attempt.json','records/diagnostic_submission_response.json','records/scheduler_jobs.json','evidence/replay_identity.json','evidence/failed_batch_start_identity.json','evidence/diagnostic_result.json']:
    report[name]=record(ROOT/name)
mapping=report['records/scheduler_jobs.json'].get('value',{})
spec=report['diagnostic_spec.json'].get('value',{})
report['source_and_duplicate_guard_queries']=[]
if spec:
    report['source_and_duplicate_guard_queries']=[query(['squeue','-h','-u','sunyiq','-o','%i|%j|%T|%R|%N']),query(['sacct','-n','-X','-j',str(spec['source_job']),'--format=JobID,JobName,State,ExitCode,Elapsed,NodeList,Reason','-P'])]
jobs=[str(x) for x in mapping.values()];assert all(x.isdigit() for x in jobs)
report['scheduler_queries']=[]
if jobs:
    ids=','.join(jobs);report['scheduler_queries']=[query(['squeue','-h','-j',ids,'-o','%i|%j|%T|%R|%N|%M']),query(['sacct','-n','-X','-j',ids,'--format=JobID,JobName,State,ExitCode,Elapsed,NodeList,Reason','-P'])]
report['logs']=[]
for p in sorted((ROOT/'logs').glob('*.out')):
    d=record(p,False)
    with p.open('rb') as f:f.seek(max(0,d['bytes']-60000));d['tail']=f.read().decode('utf-8','replace')
    report['logs'].append(d)
p=ROOT/'evidence/events.jsonl';report['events']=record(p,False)
if p.exists():
    with p.open('rb') as f:f.seek(max(0,p.stat().st_size-120000));tail=f.read().decode('utf-8','replace')
    rows=[]
    for line in tail.splitlines():
        try: rows.append(json.loads(line))
        except json.JSONDecodeError:pass
    report['events']['recent_rows']=rows[-5:]
print(json.dumps(report,sort_keys=True,allow_nan=False))
PY
