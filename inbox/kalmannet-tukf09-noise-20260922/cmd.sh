#!/bin/bash
set -eo pipefail
python='/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python'
export PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1
unset PYTHONPATH
"$python" -B - <<'PY'
from datetime import datetime, timezone
import hashlib,json,os,pathlib,stat,subprocess,time
root=pathlib.Path('/data1/home/sunyiq/kalmannet_tukf09_protection_diagnostic_20261001_attempt1')
assert root.is_dir() and not root.is_symlink()
def small(path,limit=65536,mutable=False):
    if not path.exists():
        return None
    info=path.lstat()
    assert stat.S_ISREG(info.st_mode) and info.st_nlink==1 and info.st_size<=limit
    data=path.read_bytes()
    try:
        return json.loads(data)
    except json.JSONDecodeError as exc:
        if not mutable:
            raise
        return {'status':'TRANSIENT_PARTIAL_READ','path':str(path.relative_to(root)),
                'captured_bytes':len(data),'sha256':hashlib.sha256(data).hexdigest(),
                'raw_prefix':data[:1024].decode(errors='replace'),'error':str(exc)}
submission=small(root/'control'/'submission_confirmed.json')
assert submission and submission['status']=='SINGLE_SYNTHETIC_JOB_SUBMISSION_CONFIRMED'
job=str(submission['job_id'])
assert job.isascii() and job.isdigit()
queries={}
for label,command in [('sacct',['sacct','-j',job,'-P','--format=JobID,State,ExitCode,Elapsed,MaxRSS,NodeList,AllocCPUS,Start,End']),
                     ('squeue',['squeue','-j',job,'-h','-o','%i|%P|%T|%C|%M|%R'])]:
    try:
        result=subprocess.run(command,capture_output=True,timeout=30)
        assert len(result.stdout)+len(result.stderr)<65536
        queries[label]={'returncode':result.returncode,'stdout':result.stdout.decode(errors='replace'),
                        'stderr':result.stderr.decode(errors='replace')}
    except Exception as exc:
        queries[label]={'read_only_query_error':repr(exc)}
results=root/'results'
markers={name:small(results/name) for name in ('started.json','shorts_complete.json','long_started.json',
                                              'result.json','complete.json','failed.json','failure.json')}
cases=[]
if (results/'configs').is_dir():
    for path in sorted((results/'configs').glob('*.json')):
        config=small(path)
        name=config['case_id']
        assert isinstance(name,str) and len(name)<128 and '/' not in name
        out=results/'cases'/name
        outer=results/'outer'/name
        supervisor=small(out/'supervisor.json',mutable=True)
        guard=small(out/'guard.result.json')
        assertions=small(outer/'independent_assertions.json')
        progress={'case_id':name,'supervisor':supervisor,'guard':guard,
                  'worker_started':small(out/'worker'/'started.json'),
                  'worker_completed':small(out/'worker'/'completed.json'),
                  'assertions_passed':assertions.get('passed') if assertions else None,
                  'failed_checks':[key for key,value in assertions.get('checks',{}).items() if not value] if assertions else None}
        cases.append(progress)
inventory=[]
for path in root.rglob('*'):
    info=path.lstat()
    assert not stat.S_ISLNK(info.st_mode)
    if stat.S_ISREG(info.st_mode):
        assert info.st_nlink==1
        inventory.append({'path':str(path.relative_to(root)), 'bytes':info.st_size,'mtime_ns':info.st_mtime_ns})
    else:
        assert stat.S_ISDIR(info.st_mode)
assert len(inventory)<16384
summary={'read_only_capture_time_unix':time.time(),
         'read_only_capture_time_iso_utc':datetime.now(timezone.utc).isoformat(),
         'job_id':int(job),'queries':queries,
         'markers':markers,'cases':cases,'file_count':len(inventory),
         'total_root_bytes':sum(x['bytes'] for x in inventory),
         'payload_manifest_sha256':hashlib.sha256((root/'payload_manifest.json').read_bytes()).hexdigest(),
         'diagnostic_data_only':True,'no_job_changes':True}
print('READ_ONLY_SYNTHETIC_STATUS '+json.dumps(summary,sort_keys=True),flush=True)
PY
