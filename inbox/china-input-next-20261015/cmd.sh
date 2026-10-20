#!/bin/bash
set -eo pipefail
umask 077
export PYTHONDONTWRITEBYTECODE=1 CUDA_VISIBLE_DEVICES=''
exec timeout --signal=TERM --kill-after=3s 180s /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'GEOLOGY_ARCHIVE'
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

ROOT=Path('/data1/home/sunyiq/china_input_completion_hpc_20261015_001/geology_original_archive_login_transfer_20261020_v2')
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
    assert set(payload)=={'CONTRACT.json','geology_archive_hpc_transfer_20261020_v2.py','geology_archive_hpc_transfer_20261020_v2.sbatch'}
    ROOT.mkdir(mode=0o700);(ROOT/'logs').mkdir()
    deployed={}
    for name,item in payload.items():
        raw=base64.b64decode(item['base64'],validate=True)
        assert len(raw)==item['bytes']<=131072 and hashlib.sha256(raw).hexdigest()==item['sha256']
        with (ROOT/name).open('xb') as stream:stream.write(raw)
        assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==item['sha256']
        deployed[name]=item['sha256']
    save('DEPLOYMENT.json',dict(files=deployed,source_gets=0,credential_content_read=False,server_utc=utc()))
    transfer_start=time.monotonic()
    transfer=query(['/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python','-B',str(ROOT/'geology_archive_hpc_transfer_20261020_v2.py'),'transfer'],120)
    transfer['seconds_before_save']=time.monotonic()-transfer_start
    save('TRANSFER_PROCESS.json',transfer)
    assert time.monotonic()-transfer_start<=120 and not (ROOT/'TRANSFER_FAILURE.json').exists(), 'TRANSFER_FINAL_BUDGET_FAILED_NO_JOB'
    assert transfer['exit_code']==0, 'SOURCE_TRANSFER_FAILED_NO_JOB_SUBMITTED'
    accepted=json.loads((ROOT/'TRANSFER_RESULT.json').read_bytes())
    assert accepted['status']=='ORIGINAL_BYTES_VERIFIED' and accepted['bytes']==36248447 and accepted['official_md5']=='f42c5f1b9ddbc74ab41d2ad0d46ba3d5'
    save('SUBMISSION_STARTED.json',dict(max_new_jobs=1,automatic_retries=0,server_utc=utc()))
    result=query(['sbatch',str(ROOT/'geology_archive_hpc_transfer_20261020_v2.sbatch')],15)
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
        'TRANSFER_STARTED.json','TRANSFER_PROCESS.json','TRANSFER_RESULT.json','TRANSFER_FAILURE.json','RECOVERY_STARTED.json','HTTP_HEADERS.json','ARCHIVE_MEMBERS.json','RECOVERY_RESULT.json','RECOVERY_FAILURE.json']
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
