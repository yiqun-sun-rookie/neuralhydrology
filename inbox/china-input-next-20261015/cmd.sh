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
