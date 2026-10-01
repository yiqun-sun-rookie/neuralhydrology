#!/bin/bash
set -eo pipefail
umask 027
python='/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python'
export PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1
unset PYTHONPATH
"$python" -B - <<'PY'
import hashlib,json,os,pathlib,subprocess,time
root=pathlib.Path('/data1/home/sunyiq/kalmannet_tukf09_protection_diagnostic_20261001_attempt1')
for parent in (root,*root.parents):
    assert parent.is_dir() and not parent.is_symlink()
def read(name):
    path=root/name
    info=path.lstat()
    assert path.is_file() and not path.is_symlink() and info.st_nlink==1
    assert info.st_size<1048576
    return path.read_bytes()
manifest_raw=read('payload_manifest.json')
assert hashlib.sha256(manifest_raw).hexdigest()=='b4a6b0158fcd6e88ba80688d0d92f6c7ae7ba334b79f89f256889173795ddaf6'
manifest=json.loads(manifest_raw)
assert len(manifest['members'])==9
bindings={}
for x in manifest['members']:
    assert '/' not in x['path'] and '\\' not in x['path'] and x['path'] not in bindings
    b=read(x['path'])
    assert len(b)==x['bytes'] and hashlib.sha256(b).hexdigest()==x['sha256']
    bindings[x['path']]=x['sha256']
review_raw=read('control/independent_static_review.json')
assert hashlib.sha256(review_raw).hexdigest()=='4a0ea158080fee446cb735b81e7c736085e247c5ce26438934451ed0e7dfb784'
review=json.loads(review_raw)
assert review['admission']=='PASS' and review['payload_member_sha256']==bindings
deployment=json.loads(read('control/deployment.json'))
assert deployment['status']=='ISOLATED_DEPLOYMENT_VERIFIED_NO_DIAGNOSTIC_EXECUTION'
assert deployment['payload_manifest_sha256']=='b4a6b0158fcd6e88ba80688d0d92f6c7ae7ba334b79f89f256889173795ddaf6'
auth=json.loads(read('authorization.json')); contract=json.loads(read('diagnostic_contract.json'))
assert auth['maximum_scheduler_submissions']==contract['maximum_submissions']==1
assert auth['requested_cpus']==contract['requested_cpus']==1
assert auth['scheduler_time_limit_seconds']==contract['job_seconds']==9000
assert auth['gpu_requested'] is False and contract['automatic_retry'] is False
assert not os.path.lexists(str(root/'results')) and not os.path.lexists(str(root/'control'/'io_budget.state'))
script=read('diagnostic_job.slurm').decode()
for required in ('#SBATCH --cpus-per-task=1','#SBATCH --time=02:30:00','#SBATCH --no-requeue','#SBATCH --nice=10000'):
    assert required in script
assert '--gres' not in script and '--array' not in script and '--exclusive' not in script
def exclusive(name,value):
    b=(json.dumps(value,sort_keys=True,indent=2)+'\n').encode()
    assert len(b)<8192
    fd=os.open(str(root/'control'/name),os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
    with os.fdopen(fd,'wb') as f:
        f.write(b);f.flush();os.fsync(f.fileno())
exclusive('submission_attempt.json',{'status':'ONE_SUBMISSION_ATTEMPT_CONSUMED','time_unix':time.time(),
           'payload_manifest_sha256':'b4a6b0158fcd6e88ba80688d0d92f6c7ae7ba334b79f89f256889173795ddaf6','independent_review_sha256':'4a0ea158080fee446cb735b81e7c736085e247c5ce26438934451ed0e7dfb784',
           'maximum_submissions':1,'no_automatic_retry':True})
try:
    result=subprocess.run(['sbatch','--parsable',str(root/'diagnostic_job.slurm')],
                         cwd=root,capture_output=True,timeout=60)
except BaseException as exc:
    exclusive('submission_unknown.json',{'status':'SUBMISSION_OUTCOME_UNKNOWN_NO_RETRY',
                                         'type':type(exc).__name__,'error':str(exc)[:4096]})
    raise
assert len(result.stdout)+len(result.stderr)<16384
text=result.stdout.decode('utf-8',errors='strict').strip()
exclusive('submission_raw.json',{'returncode':result.returncode,'stdout':text,
                                  'stderr':result.stderr.decode('utf-8',errors='replace')})
assert result.returncode==0 and text.isdigit(), 'unique scheduler job id not confirmed; no retry'
job=int(text)
record={'status':'SINGLE_SYNTHETIC_JOB_SUBMISSION_CONFIRMED','job_id':job,'time_unix':time.time(),
        'payload_manifest_sha256':'b4a6b0158fcd6e88ba80688d0d92f6c7ae7ba334b79f89f256889173795ddaf6','requested_cpus':1,'gpu_requested':False,
        'scheduler_seconds':9000,'maximum_parallel_synthetic_workers':1,'maximum_submissions':1,
        'scientific_model_execution':False,'automatic_retry':False}
exclusive('submission_confirmed.json',record)
print('SINGLE_SUBMISSION_CONFIRMED '+json.dumps(record,sort_keys=True),flush=True)
for label,command in [('SCONTROL',['scontrol','show','job',str(job),'-o']),
                      ('SQUEUE',['squeue','-j',str(job),'-h','-o','%i|%P|%T|%C|%M|%R'])]:
    try:
        query=subprocess.run(command,capture_output=True,timeout=20)
        assert len(query.stdout)+len(query.stderr)<16384
        print(label+' '+json.dumps({'returncode':query.returncode,'stdout':query.stdout.decode(errors='replace'),
                                    'stderr':query.stderr.decode(errors='replace')},sort_keys=True),flush=True)
    except Exception as exc:
        print(label+'_READ_ONLY_QUERY_UNAVAILABLE '+repr(exc),flush=True)
PY
