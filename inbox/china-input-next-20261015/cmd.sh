#!/bin/bash
set -eo pipefail
umask 077
export CUDA_VISIBLE_DEVICES='' PYTHONDONTWRITEBYTECODE=1
exec timeout --signal=TERM --kill-after=3s 420s /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'C3_RESTORE'
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

ROOT=Path('/data1/home/sunyiq/china_input_completion_hpc_20261015_001/common_source_restoration_20261019_v1')
TRANSPORT=Path('/data1/home/sunyiq/china_input_completion_hpc_20261015_001/common_source_transport_20261020_v1')
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
    assert set(payload)=={'CONTRACT.json','c3_source_restore_main_20261020_v1.py',
        'c3_source_restore_independent_20261020_v1.py','c3_source_restore_control_20261020_v1.py',
        'c3_source_restore_20261020_v1.sbatch'}
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
    assert contract['private_branch']=='codex/china-input-transport-20261020-v1'
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
    submitted=query(['sbatch',str(ROOT/'c3_source_restore_20261020_v1.sbatch')],15)
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
        'CONTROL_FAILURE.json','RESTORE_STARTED.json','RESTORED_FILES.json','RESTORE_RESULT.json','RESTORE_FAILURE.json',
        'INDEPENDENT_STARTED.json','INDEPENDENT_FILES.json','INDEPENDENT_RESULT.json','INDEPENDENT_FAILURE.json',
        ]
    if job is not None:names += ['logs/restore-'+job+'.out','logs/restore-'+job+'.err']
    for name in ('c3_source_restore_main_20261020_v1.py','c3_source_restore_independent_20261020_v1.py'):
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
    print('SOURCE_RESTORE_BYTES='+str(len(raw)))
    print('SOURCE_RESTORE_SHA256='+hashlib.sha256(raw).hexdigest())
    print('SOURCE_RESTORE_ZLIB_BASE64='+base64.b64encode(zlib.compress(raw)).decode())
    print('SOURCE_RESTORE_DONE',flush=True)


if __name__=='__main__':
    main()

C3_RESTORE
