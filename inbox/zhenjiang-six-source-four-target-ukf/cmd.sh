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
    report['source_and_duplicate_guard_queries']=[query(['squeue','-h','-u','sunyiq','-o','%i|%j|%T|%R|%N']),query(['sacct','-n','-X','-j',str(spec['source_job']),'--format=JobID,JobName,State,ExitCode,Elapsed,NodeList,Reason','-P']),query(['sacct','-n','-X','-j',str(spec['source_job']),'--format=JobID,State,ExitCode','-P'])]
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
set -euo pipefail
python3 - <<'PY'
"""Inspect only the registered diagnostic job and its scheduling constraints."""
import datetime
import json
from pathlib import Path
import subprocess

root = Path('/data1/home/sunyiq/zhenjiang_gradient_diagnostic_20261011_001')
jobs = json.loads((root / 'records/scheduler_jobs.json').read_text())
spec = json.loads((root / 'diagnostic_spec.json').read_text())
job = str(jobs['gradient_diagnostic'])
assert job.isdigit()
commands = [
    ['scontrol', 'show', 'job', '-o', job],
    ['squeue', '-h', '-j', job, '-o', '%i|%j|%T|%R|%N|%M|%V|%S'],
    ['sacct', '-n', '-X', '-j', job, '--format=JobID,JobName,State,ExitCode,Elapsed,NodeList,Reason', '-P'],
    ['sprio', '-j', job, '-l'],
    ['sinfo', '-h', '-p', 'hgpu2p', '-N', '-o', '%N|%T|%G|%C|%m'],
]
queries = []
for command in commands:
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=30)
        queries.append({'command': command, 'returncode': result.returncode,
                        'stdout': result.stdout, 'stderr': result.stderr})
    except (OSError, subprocess.TimeoutExpired) as exc:
        queries.append({'command': command, 'error': str(exc)})
print(json.dumps({'schema': 'read_only_registered_diagnostic_queue_detail_v1',
                  'checked_at_beijing': datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
                  'diagnostic_root': str(root), 'job_id': job, 'expected_job_name': spec['job_name'],
                  'queries': queries, 'scheduler_mutated': False, 'training_data_read': False,
                  'evaluation_values_read': False}, sort_keys=True))
PY
