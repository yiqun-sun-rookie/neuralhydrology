#!/bin/bash
set -eo pipefail
umask 077
export PYTHONDONTWRITEBYTECODE=1 CUDA_VISIBLE_DEVICES=''
exec timeout --signal=TERM --kill-after=3s 120s /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'SDK_RUNTIME'
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

ROOT=Path('/data1/home/sunyiq/china_input_completion_hpc_20261015_001/weather_ee_runtime_20261020_v2')
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
    assert not ROOT.exists(),'NEW_ROOT_ALREADY_EXISTS_NO_REPLAY'
    assert ROOT.parent.resolve(strict=True)==ROOT.parent and shutil.disk_usage(ROOT.parent).free>=2*1024**3
    payload=json.loads(zlib.decompress(base64.b64decode(PAYLOAD_B64,validate=True)))
    assert set(payload)=={'CONTRACT.json','requirements.txt','install_weather_ee_runtime_20261020_v2.py','weather_ee_runtime_20261020_v2.sbatch'}
    ROOT.mkdir(mode=0o700);(ROOT/'logs').mkdir()
    deployed={}
    for name,item in payload.items():
        raw=base64.b64decode(item['base64'],validate=True)
        assert len(raw)==item['bytes']<=131072 and hashlib.sha256(raw).hexdigest()==item['sha256']
        with (ROOT/name).open('xb') as stream:stream.write(raw)
        assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==item['sha256']
        deployed[name]=item['sha256']
    save('DEPLOYMENT.json',dict(files=deployed,source_gets=0,credential_content_read=False,server_utc=utc()))
    save('SUBMISSION_STARTED.json',dict(max_new_jobs=1,automatic_retries=0,server_utc=utc()))
    result=query(['sbatch',str(ROOT/'weather_ee_runtime_20261020_v2.sbatch')],15)
    save('SUBMISSION_RESULT.json',result)
    found=re.findall(r'^Submitted batch job ([0-9]+)\s*$',result['stdout'],re.M)
    assert result['exit_code']==0 and len(found)==1,'UNKNOWN_SUBMISSION_NEVER_REPLAY'
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
        'INSTALL_STARTED.json','INSTALL_RESULT.json','INSTALL_FAILURE.json','WHEEL_IDENTITIES.json','PIP_INSTALL_REPORT.json',
        'INSTALLED_FILES.json','IMPORT_VERIFICATION.json']
    if job is not None:names += ['logs/sdk-'+job+'.out','logs/sdk-'+job+'.err']
    for name in ('DOWNLOAD','OFFLINE_INSTALL','IMPORT_ONLY','AUTH_HELP_ONLY'):
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
    value=dict(root=str(ROOT),job_id=job,mode=MODE,server_utc=utc(),
        queries=queries,records=records,seconds=time.monotonic()-START,model_calls=0,automatic_checks_enabled=False,
        bridge_error=bridge_error,job_status='CONFIRMED_SUBMISSION_ID' if job is not None else 'NO_CONFIRMED_JOB')
    raw=json.dumps(value,ensure_ascii=False,separators=(',',':')).encode();assert len(raw)<=6*1024**2
    print('SDK_RUNTIME_BYTES='+str(len(raw)))
    print('SDK_RUNTIME_SHA256='+hashlib.sha256(raw).hexdigest())
    print('SDK_RUNTIME_ZLIB_BASE64='+base64.b64encode(zlib.compress(raw)).decode())
    print('SDK_RUNTIME_DONE',flush=True)


if __name__=='__main__':
    main()

SDK_RUNTIME
