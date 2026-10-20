#!/bin/bash
set -eo pipefail
umask 077
export PYTHONDONTWRITEBYTECODE=1 CUDA_VISIBLE_DEVICES=''
exec timeout --signal=TERM --kill-after=3s 420s /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'SDK_OFFLINE'
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

ROOT=Path('/data1/home/sunyiq/china_input_completion_hpc_20261015_001/weather_ee_offline_20261020_v1')
TRANSPORT=Path('/data1/home/sunyiq/china_input_completion_hpc_20261015_001/weather_ee_offline_transport_20261020_v1')
MODE='status'
PAYLOAD_B64=''
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
    assert set(payload)=={'CONTRACT.json','requirements.txt','install_weather_ee_offline_20261020_v1.py','weather_ee_offline_20261020_v1.sbatch'}
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
    assert contract['private_branch']=='codex/china-weather-sdk-offline-20261020-v1'
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
    submitted=query(['sbatch',str(ROOT/'weather_ee_offline_20261020_v1.sbatch')],15)
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
    names=['BRIDGE_FAILURE.json','DEPLOYMENT.json','SUBMISSION_STARTED.json','SUBMISSION_RESULT.json','OWN_JOB_ID',
        'FETCH_STARTED.json','FETCH_RESULT.json','GIT_INIT_RESULT.json','INSTALL_STARTED.json','INSTALL_RESULT.json',
        'INSTALL_FAILURE.json','WHEEL_IDENTITIES.json','PIP_INSTALL_REPORT.json','INSTALLED_FILES.json',
        'IMPORT_VERIFICATION.json','MATERIALIZED_SOFTWARE.json']
    if job is not None:names += ['logs/sdk-'+job+'.out','logs/sdk-'+job+'.err']
    for name in ('OFFLINE_INSTALL','IMPORT_ONLY','AUTH_HELP_ONLY'):
        names += [name+'_EXIT.json',name+'.stdout',name+'.stderr']
    records={};total=0
    for name in names:
        path=ROOT/name
        if not path.exists():records[name]=dict(present=False);continue
        assert path.resolve(strict=True)==path and path.is_file() and not path.is_symlink()
        before=path.stat();assert before.st_size<=2*1048576
        raw=path.read_bytes();after=path.stat()
        assert (before.st_size,before.st_mtime_ns)==(after.st_size,after.st_mtime_ns) and len(raw)==before.st_size
        total+=len(raw);assert total<=4*1024**2
        records[name]=dict(present=True,bytes=len(raw),sha256=hashlib.sha256(raw).hexdigest(),
            base64=base64.b64encode(raw).decode())
    value=dict(root=str(ROOT),transport_root=str(TRANSPORT),job_id=job,mode=MODE,server_utc=utc(),
        queries=queries,records=records,seconds=time.monotonic()-START,model_calls=0,automatic_checks_enabled=False,
        bridge_error=bridge_error,job_status='CONFIRMED_SUBMISSION_ID' if job is not None else 'NO_CONFIRMED_JOB')
    raw=json.dumps(value,ensure_ascii=False,separators=(',',':')).encode();assert len(raw)<=6*1024**2
    print('SDK_OFFLINE_BYTES='+str(len(raw)))
    print('SDK_OFFLINE_SHA256='+hashlib.sha256(raw).hexdigest())
    print('SDK_OFFLINE_ZLIB_BASE64='+base64.b64encode(zlib.compress(raw)).decode())
    print('SDK_OFFLINE_DONE',flush=True)


if __name__=='__main__':
    main()

SDK_OFFLINE
