#!/bin/bash
set -eo pipefail
umask 077
export PYTHONDONTWRITEBYTECODE=1 CUDA_VISIBLE_DEVICES=''
exec timeout --signal=TERM --kill-after=3s 120s /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'SDK_VALIDATION'
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

ROOT=Path('/data1/home/sunyiq/china_input_completion_hpc_20261015_001/weather_ee_validation_20261020_v1')
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
    assert set(payload)=={'verify_weather_ee_imports_20261020_v1.py','CONTRACT.json','requirements.txt','validate_weather_ee_existing_20261020_v1.py','weather_ee_validation_20261020_v1.sbatch'}
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
    result=query(['sbatch',str(ROOT/'weather_ee_validation_20261020_v1.sbatch')],15)
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
        'VALIDATION_STARTED.json','VALIDATION_RESULT.json','VALIDATION_FAILURE.json','IMPORT_CONTEXT.json',
        'IMPORT_VERIFICATION.json','CLI_IDENTITY.json','INSTALLED_FILES.json']
    if job is not None:names += ['logs/sdk-'+job+'.out','logs/sdk-'+job+'.err']
    for name in ('IMPORT_ONLY','AUTH_HELP_ONLY'):
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
    print('SDK_VALIDATION_BYTES='+str(len(raw)))
    print('SDK_VALIDATION_SHA256='+hashlib.sha256(raw).hexdigest())
    print('SDK_VALIDATION_ZLIB_BASE64='+base64.b64encode(zlib.compress(raw)).decode())
    print('SDK_VALIDATION_DONE',flush=True)


if __name__=='__main__':
    main()

SDK_VALIDATION
