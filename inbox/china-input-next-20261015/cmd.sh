#!/bin/bash
set -eo pipefail
umask 077
export CUDA_VISIBLE_DEVICES='' PYTHONDONTWRITEBYTECODE=1
exec timeout --signal=TERM --kill-after=3s 420s /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'BOUNDARY'
"""Private original-byte fetch and one isolated Slurm submission, or exact own-job status."""
import base64
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time
import zlib

ROOT=Path('/data1/home/sunyiq/china_input_completion_hpc_20261015_001/weather_boundary_25207_20261020_v1')
TRANSPORT=Path('/data1/home/sunyiq/china_input_completion_hpc_20261015_001/weather_boundary_transport_20261020_v1')
MODE='deploy'
PAYLOAD_B64='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'
START=time.monotonic()


def utc():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def save(name,value):
    raw=(json.dumps(value,ensure_ascii=False,indent=2)+'\n').encode()
    assert len(raw)<=1048576
    with (ROOT/name).open('xb') as stream:stream.write(raw)


def query(command,seconds=9):
    try:
        result=subprocess.run(command,stdin=subprocess.DEVNULL,capture_output=True,timeout=seconds)
    except subprocess.TimeoutExpired as error:
        return dict(command=command,exit_code=None,stdout=(error.stdout or b'').decode(errors='replace')[:131072],
            stderr=(error.stderr or b'').decode(errors='replace')[:131072],error='QUERY_TIMEOUT_UNKNOWN',server_utc=utc())
    assert len(result.stdout)<=131072 and len(result.stderr)<=131072
    return dict(command=command,exit_code=result.returncode,stdout=result.stdout.decode(errors='replace'),
        stderr=result.stderr.decode(errors='replace'),server_utc=utc())


def deploy():
    assert not ROOT.exists() and not TRANSPORT.exists(),'NEW_ROOT_ALREADY_EXISTS_NO_REPLAY'
    assert ROOT.parent.resolve(strict=True)==ROOT.parent and shutil.disk_usage(ROOT.parent).free>=3*1024**3
    payload=json.loads(zlib.decompress(base64.b64decode(PAYLOAD_B64,validate=True)))
    assert set(payload)=={'CONTRACT.json','c3_boundary_main_20261020_v2.py',
        'c3_boundary_independent_20261020_v2.py','c3_boundary_control_20261020_v3.py',
        'c3_boundary_20261020_v3.sbatch'}
    ROOT.mkdir(mode=0o700);(ROOT/'logs').mkdir();TRANSPORT.mkdir(mode=0o700)
    deployed={}
    for name,row in payload.items():
        raw=base64.b64decode(row['base64'],validate=True)
        assert len(raw)==row['bytes']<=131072 and hashlib.sha256(raw).hexdigest()==row['sha256']
        with (ROOT/name).open('xb') as stream:stream.write(raw)
        assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==row['sha256']
        deployed[name]=row['sha256']
    contract=json.loads((ROOT/'CONTRACT.json').read_bytes())
    assert contract['root']==str(ROOT) and contract['bare_git']==str(TRANSPORT/'private_git')
    assert contract['private_repository']=='yiqun-sun-rookie/forecast_system_lite'
    assert contract['private_branch']=='codex/china-weather-boundary-20261020-v1'
    assert re.fullmatch('[0-9a-f]{40}',contract['private_commit'])
    save('FETCH_STARTED.json',dict(repository=contract['private_repository'],commit=contract['private_commit'],
        maximum_attempts=1,scientific_values_parsed=0,server_utc=utc()))
    bare=TRANSPORT/'private_git'
    init=query(['git','init','--bare',str(bare)],10);save('GIT_INIT_RESULT.json',init)
    assert init['exit_code']==0
    env=dict(os.environ,GIT_TERMINAL_PROMPT='0',GIT_ASKPASS='/bin/false',SSH_ASKPASS='/bin/false')
    command=['timeout','--signal=TERM','--kill-after=3s','300s','git','--git-dir='+str(bare),
        'fetch','--quiet','--no-tags','--depth=1','git@github.com:'+contract['private_repository']+'.git',
        'refs/heads/'+contract['private_branch']]
    fetched=subprocess.run(command,stdin=subprocess.DEVNULL,capture_output=True,timeout=305,
        env=env,start_new_session=True)
    assert len(fetched.stdout)<=131072 and len(fetched.stderr)<=131072
    save('FETCH_RESULT.json',dict(exit_code=fetched.returncode,stdout=fetched.stdout.decode(errors='replace'),
        stderr=fetched.stderr.decode(errors='replace'),server_utc=utc()))
    assert fetched.returncode==0,'PRIVATE_FETCH_FAILED_NO_RETRY'
    commit=query(['git','--git-dir='+str(bare),'rev-parse','FETCH_HEAD'])
    assert commit['exit_code']==0 and commit['stdout'].strip()==contract['private_commit']
    gitbytes=sum(p.stat().st_size for p in TRANSPORT.rglob('*') if p.is_file())
    assert gitbytes<=512*1024**2
    save('DEPLOYMENT.json',dict(files=deployed,private_commit=commit,private_git_bytes=gitbytes,
        scientific_values_parsed=0,server_utc=utc()))
    save('SUBMISSION_STARTED.json',dict(max_new_jobs=1,automatic_retries=0,server_utc=utc()))
    submitted=query(['sbatch',str(ROOT/'c3_boundary_20261020_v3.sbatch')],15)
    save('SUBMISSION_RESULT.json',submitted)
    found=re.findall(r'^Submitted batch job ([0-9]+)\s*$',submitted['stdout'],re.M)
    assert submitted['exit_code']==0 and len(found)==1,'UNKNOWN_SUBMISSION_NEVER_REPLAY'
    job=found[0]
    with (ROOT/'OWN_JOB_ID').open('x') as stream:stream.write(job+'\n')
    return job


def main():
    job=None;bridge_error=None
    try:
        if MODE=='deploy':
            job=deploy()
        else:
            assert MODE=='status' and ROOT.resolve(strict=True)==ROOT
            job=(ROOT/'OWN_JOB_ID').read_text().strip()
        assert re.fullmatch('[0-9]+',job)
    except BaseException as error:
        job=None
        bridge_error=dict(error_type=type(error).__name__,error=str(error),server_utc=utc())
        if MODE=='deploy' and ROOT.is_dir() and not (ROOT/'BRIDGE_FAILURE.json').exists():
            save('BRIDGE_FAILURE.json',bridge_error)
    queries={}
    if job is not None:
        queries=dict(squeue=query(['squeue','-h','-j',job,'-o','%i|%T|%N|%R|%Z']),
            sacct=query(['sacct','-X','-S','2026-10-20','-j',job,'--noheader','--parsable2',
                '--format=JobIDRaw,State,ExitCode,NodeList,WorkDir%240,Start,End,Elapsed,AllocCPUS,MaxRSS']),
            scontrol=query(['scontrol','show','job',job,'-o']))
    names=['BRIDGE_FAILURE.json','FETCH_STARTED.json','GIT_INIT_RESULT.json','FETCH_RESULT.json','DEPLOYMENT.json',
        'SUBMISSION_STARTED.json','SUBMISSION_RESULT.json','OWN_JOB_ID','CONTROL_STARTED.json','CONTROL_RESULT.json',
        'CONTROL_FAILURE.json','BOUNDARY_MAIN.json','BOUNDARY_INDEPENDENT.json','GEOLOGY_CANDIDATE_NAMES.json']
    if job is not None:names += ['logs/boundary-'+job+'.out','logs/boundary-'+job+'.err']
    for name in ('c3_boundary_main_20261020_v2.py','c3_boundary_independent_20261020_v2.py'):
        names += [name+'_EXIT.json',name+'.stdout',name+'.stderr']
    records={};total=0
    for name in names:
        path=ROOT/name
        if not path.exists():records[name]=dict(present=False);continue
        assert path.resolve(strict=True)==path and path.is_file() and not path.is_symlink()
        before=path.stat();assert before.st_size<=1048576
        raw=path.read_bytes();after=path.stat()
        assert (before.st_size,before.st_mtime_ns)==(after.st_size,after.st_mtime_ns) and len(raw)==before.st_size
        total+=len(raw);assert total<=4*1024**2
        records[name]=dict(present=True,bytes=len(raw),sha256=hashlib.sha256(raw).hexdigest(),
            base64=base64.b64encode(raw).decode())
    value=dict(root=str(ROOT),transport_root=str(TRANSPORT),job_id=job,mode=MODE,server_utc=utc(),
        queries=queries,records=records,seconds=time.monotonic()-START,model_calls=0,automatic_checks_enabled=False,
        bridge_error=bridge_error,job_status='CONFIRMED_SUBMISSION_ID' if job is not None else 'NO_CONFIRMED_JOB')
    raw=json.dumps(value,ensure_ascii=False,separators=(',',':')).encode();assert len(raw)<=6*1024**2
    print('BOUNDARY_DIAG_BYTES='+str(len(raw)))
    print('BOUNDARY_DIAG_SHA256='+hashlib.sha256(raw).hexdigest())
    print('BOUNDARY_DIAG_ZLIB_BASE64='+base64.b64encode(zlib.compress(raw)).decode())
    print('BOUNDARY_DIAG_DONE',flush=True)


if __name__=='__main__':
    main()

BOUNDARY
