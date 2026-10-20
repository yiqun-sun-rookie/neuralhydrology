#!/bin/bash
set -eo pipefail
umask 077
export PYTHONDONTWRITEBYTECODE=1 CUDA_VISIBLE_DEVICES=''
exec timeout --signal=TERM --kill-after=3s 120s /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'GEOLOGY_ARCHIVE'
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

ROOT=Path('/data1/home/sunyiq/china_input_completion_hpc_20261015_001/geology_original_archive_20261020_v1')
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
    assert set(payload)=={'CONTRACT.json','recover_geology_original_archive_20261020_v1.py','geology_original_archive_20261020_v1.sbatch'}
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
    result=query(['sbatch',str(ROOT/'geology_original_archive_20261020_v1.sbatch')],15)
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
        'RECOVERY_STARTED.json','HTTP_HEADERS.json','ARCHIVE_MEMBERS.json','RECOVERY_RESULT.json','RECOVERY_FAILURE.json']
    if job is not None:names += ['logs/archive-'+job+'.out','logs/archive-'+job+'.err']
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
    print('GEOLOGY_ARCHIVE_BYTES='+str(len(raw)))
    print('GEOLOGY_ARCHIVE_SHA256='+hashlib.sha256(raw).hexdigest())
    print('GEOLOGY_ARCHIVE_ZLIB_BASE64='+base64.b64encode(zlib.compress(raw)).decode())
    print('GEOLOGY_ARCHIVE_DONE',flush=True)


if __name__=='__main__':
    main()

GEOLOGY_ARCHIVE
