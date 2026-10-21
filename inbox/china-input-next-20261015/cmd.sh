#!/bin/bash
set -eo pipefail
umask 077
export PYTHONDONTWRITEBYTECODE=1 CUDA_VISIBLE_DEVICES=''
exec timeout --signal=TERM --kill-after=5s 120s /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'NATIVE_AUDIT'
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

ROOT=Path('/data1/home/sunyiq/china_input_completion_hpc_20261015_001/glhymps_three_geometry_20261021_v1')
MODE='status'
PAYLOAD_B64=''
START=time.monotonic()
OWNED=False


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
    global OWNED
    assert not ROOT.exists(),'NEW_ROOT_ALREADY_EXISTS_NO_REPLAY'
    assert ROOT.parent.resolve(strict=True)==ROOT.parent and shutil.disk_usage(ROOT.parent).free>=2*1024**3
    payload=json.loads(zlib.decompress(base64.b64decode(PAYLOAD_B64,validate=True)))
    assert set(payload)=={'CONTRACT.json', 'glhymps_three_geometry_20261021_v1.py', 'glhymps_three_geometry_20261021_v1.sbatch', 'native_glhymps_audit_20261020_v4.py', 'GEOMETRY_METADATA.json'}
    ROOT.mkdir(mode=0o700);OWNED=True;(ROOT/'logs').mkdir()
    deployed={}
    for name,item in payload.items():
        raw=base64.b64decode(item['base64'],validate=True)
        assert len(raw)==item['bytes']<=131072 and hashlib.sha256(raw).hexdigest()==item['sha256']
        with (ROOT/name).open('xb') as stream:stream.write(raw)
        assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==item['sha256']
        deployed[name]=item['sha256']
    save('DEPLOYMENT.json',dict(files=deployed,source_gets=0,credential_content_read=False,server_utc=utc()))
    save('SUBMISSION_STARTED.json',dict(max_new_jobs=1,automatic_retries=0,server_utc=utc()))
    result=query(['sbatch',str(ROOT/'glhymps_three_geometry_20261021_v1.sbatch')],15)
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
        if MODE=='deploy' and OWNED and ROOT.is_dir() and not (ROOT/'BRIDGE_FAILURE.json').exists():
            save('BRIDGE_FAILURE.json',bridge_error)
    queries={}
    if job is not None:
        queries=dict(squeue=query(['squeue','-h','-j',job,'-o','%i|%T|%N|%R|%Z']),
            sacct=query(['sacct','-X','-S','2026-10-21','-j',job,'--noheader','--parsable2',
                '--format=JobIDRaw,State,ExitCode,NodeList,WorkDir%240,Start,End,Elapsed,AllocCPUS,MaxRSS']),
            scontrol=query(['scontrol','show','job',job,'-o']))
    names=['BRIDGE_FAILURE.json', 'DEPLOYMENT.json', 'SUBMISSION_STARTED.json', 'SUBMISSION_RESULT.json', 'OWN_JOB_ID', 'COMPUTE_STARTED.json', 'REUSED_EXTRACTION.json', 'SOURCE_UNCHANGED.json', 'READER_RESULT.json', 'LAYER_INVENTORY.json', 'METHOD.json', 'COMPARISON.json', 'AUDIT_RESULT.json', 'COMPUTE_FAILURE.json', 'main/member_25878.json', 'main/member_27888.json', 'main/member_37153.json', 'independent/member_25878.json', 'independent/member_27888.json', 'independent/member_37153.json']
    if job is not None:names += ['logs/audit-'+job+'.out','logs/audit-'+job+'.err']
    records={};total=0
    for name in names:
        path=ROOT/name
        if not path.exists():records[name]=dict(present=False);continue
        assert path.resolve(strict=True)==path and path.is_file() and not path.is_symlink()
        before=path.stat();assert before.st_size<=65536
        raw=path.read_bytes();after=path.stat()
        assert (before.st_size,before.st_mtime_ns)==(after.st_size,after.st_mtime_ns) and len(raw)==before.st_size
        total+=len(raw);assert total<=4*1024**2
        records[name]=dict(present=True,bytes=len(raw),sha256=hashlib.sha256(raw).hexdigest(),
            base64=base64.b64encode(raw).decode())
    value=dict(root=str(ROOT),job_id=job,mode=MODE,server_utc=utc(),
        queries=queries,records=records,seconds=time.monotonic()-START,model_calls=0,automatic_checks_enabled=False,
        bridge_error=bridge_error,job_status='CONFIRMED_SUBMISSION_ID' if job is not None else 'NO_CONFIRMED_JOB')
    raw=json.dumps(value,ensure_ascii=False,separators=(',',':')).encode();assert len(raw)<=6*1024**2
    print('NATIVE_AUDIT_BYTES='+str(len(raw)))
    print('NATIVE_AUDIT_SHA256='+hashlib.sha256(raw).hexdigest())
    print('NATIVE_AUDIT_ZLIB_BASE64='+base64.b64encode(zlib.compress(raw)).decode())
    print('NATIVE_AUDIT_DONE',flush=True)


if __name__=='__main__':
    main()

NATIVE_AUDIT
