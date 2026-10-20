#!/bin/bash
set -eo pipefail
umask 077
export PYTHONDONTWRITEBYTECODE=1 CUDA_VISIBLE_DEVICES=''
exec timeout --signal=TERM --kill-after=3s 120s /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'GEOLOGY_MATERIALS'
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

ROOT=Path('/data1/home/sunyiq/china_input_completion_hpc_20261015_001/geology_raster_materials_20261020_v1')
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
    assert set(payload)=={'CONTRACT.json','extract_geology_raster_materials_20261020_v1.py','geology_raster_materials_20261020_v1.sbatch'}
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
    result=query(['sbatch',str(ROOT/'geology_raster_materials_20261020_v1.sbatch')],15)
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
        'MATERIALS_STARTED.json','RASTER_MATERIALS.json','MATERIALS_RESULT.json','MATERIALS_FAILURE.json']
    if job is not None:names+=['logs/materials-'+job+'.out','logs/materials-'+job+'.err']
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
    print('GEOLOGY_MATERIALS_BYTES='+str(len(raw)))
    print('GEOLOGY_MATERIALS_SHA256='+hashlib.sha256(raw).hexdigest())
    print('GEOLOGY_MATERIALS_ZLIB_BASE64='+base64.b64encode(zlib.compress(raw)).decode())
    print('GEOLOGY_MATERIALS_DONE',flush=True)


if __name__=='__main__':
    main()

GEOLOGY_MATERIALS
