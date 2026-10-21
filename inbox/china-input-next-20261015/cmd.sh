#!/bin/bash
set -eo pipefail
umask 077
export PYTHONDONTWRITEBYTECODE=1 CUDA_VISIBLE_DEVICES=''
exec timeout --signal=TERM --kill-after=5s 90s /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'GLHYMPS2_SAVED_COMPUTE'
"""Unpublished preparation: own-root byte fetch, one compute job, fixed read-only results."""
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

ROOT=Path('/data1/home/sunyiq/china_input_completion_hpc_20261015_001/glhymps2_saved_archive_27888_20261021_v1')
MODE='deploy'
PAYLOAD_B64='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'
START=time.monotonic()
OWNED=False
NAMES=['BRIDGE_FAILURE.json', 'DEPLOYMENT.json', 'SUBMISSION_STARTED.json', 'SUBMISSION_RESULT.json', 'OWN_JOB_ID', 'COMPUTE_STARTED.json', 'FETCH_STARTED.json', 'FETCH_RECORDS.json', 'ARCHIVE_IDENTITY.json', 'ZIP_MEMBERS.json', 'ZIP_DIRECTORY.json', 'NATIVE_SCHEMA.json', 'FIELD_MAPPING.json', 'RAW_SUPPORT.json', 'SOURCE_UNCHANGED.json', 'AUDIT_RESULT.json', 'COMPUTE_FAILURE.json', 'BYTE_SOURCE_VERIFICATION.json']

def utc():return datetime.datetime.now(datetime.timezone.utc).isoformat()

def sha(raw):return hashlib.sha256(raw).hexdigest()

def save(name,value):
    raw=(json.dumps(value,ensure_ascii=False,indent=2,allow_nan=False)+'\n').encode()
    assert len(raw)<=2*1024**2
    with (ROOT/name).open('xb') as f:f.write(raw)

def query(command,seconds=9,env=None):
    try:
        p=subprocess.run(command,stdin=subprocess.DEVNULL,capture_output=True,timeout=seconds,env=env)
        assert len(p.stdout)<=131072 and len(p.stderr)<=131072
        return dict(command=command,exit_code=p.returncode,stdout=p.stdout.decode(errors='replace'),stderr=p.stderr.decode(errors='replace'),server_utc=utc())
    except subprocess.TimeoutExpired as e:
        return dict(command=command,exit_code=None,error='TIMEOUT_UNKNOWN',stdout=(e.stdout or b'').decode(errors='replace')[:131072],stderr=(e.stderr or b'').decode(errors='replace')[:131072],server_utc=utc())

def deploy():
    global OWNED
    assert not ROOT.exists(),'OWN_ROOT_EXISTS_NEVER_REPLAY'
    assert ROOT.parent.resolve(strict=True)==ROOT.parent and shutil.disk_usage(ROOT.parent).free>=32*1024**3
    raw=zlib.decompress(base64.b64decode(PAYLOAD_B64,validate=True));assert len(raw)<512*1024
    payload=json.loads(raw)
    assert set(payload)=={'CONTRACT.json', 'glhymps2_saved_archive_27888_20261021_v1.sbatch', 'glhymps2_saved_archive_27888_20261021_v1.py'}
    c=json.loads(base64.b64decode(payload['CONTRACT.json']['base64'],validate=True))
    assert c['root']==str(ROOT) and c['source_acquisition_attempts']==0
    source=Path(c['byte_source']['root'])
    assert str(source)=='/data1/home/sunyiq/china_input_completion_hpc_20261015_001/glhymps2_hpc_byte_stage_20261021_v2'
    assert source.resolve(strict=True)==source
    assert set(c['byte_source']['records'])=={'ARCHIVE_IDENTITY.json','BYTE_RESULT.json','CONTROL_RESULT.json','CONTROL_FINAL.json'}
    source_records={}
    for name,desc in c['byte_source']['records'].items():
        path=source/name;assert path.resolve(strict=True)==path and not path.is_symlink()
        body=path.read_bytes();assert len(body)==desc['bytes']<=2*1024**2 and sha(body)==desc['sha256']
        source_records[name]=json.loads(body)
    assert not any((source/n).exists() for n in ('BYTE_FAILURE.json','CONTROL_FAILURE.json','BRIDGE_FAILURE.json'))
    assert source_records['CONTROL_RESULT.json']['exit_code']==0 and source_records['CONTROL_RESULT.json']['complete_logs'] is True
    assert source_records['CONTROL_RESULT.json']['body_bytes_complete_accepted'] is True
    assert source_records['CONTROL_FINAL.json']['control_sha256']==c['byte_source']['records']['CONTROL_RESULT.json']['sha256']
    assert source_records['CONTROL_FINAL.json']['body_bytes_complete_accepted'] is True
    archive=Path(c['archive']['path']);assert archive==source/'GLHYMPS2_original.zip'
    assert archive.resolve(strict=True)==archive and not archive.is_symlink() and archive.stat().st_size==2595563951
    ROOT.mkdir(mode=0o700);OWNED=True;(ROOT/'logs').mkdir()
    save('BYTE_SOURCE_VERIFICATION.json',dict(source_root=str(source),records=c['byte_source']['records'],archive_stat_bytes=archive.stat().st_size,source_gets=0))
    deployed={}
    for name,row in payload.items():
        body=base64.b64decode(row['base64'],validate=True)
        assert len(body)==row['bytes']<=131072 and sha(body)==row['sha256']
        with (ROOT/name).open('xb') as f:f.write(body)
        deployed[name]=dict(bytes=len(body),sha256=sha(body))
    c=json.loads((ROOT/'CONTRACT.json').read_bytes());assert c['root']==str(ROOT)
    save('DEPLOYMENT.json',dict(files=deployed,original_downloads=0,private_fetches=0,scientific_values_parsed=0,server_utc=utc()))
    save('SUBMISSION_STARTED.json',dict(max_new_jobs=1,automatic_retries=0,server_utc=utc()))
    sub=query(['sbatch',str(ROOT/'glhymps2_saved_archive_27888_20261021_v1.sbatch')],15);save('SUBMISSION_RESULT.json',sub)
    found=re.findall(r'^Submitted batch job ([0-9]+)\s*$',sub['stdout'],re.M)
    assert sub['exit_code']==0 and len(found)==1,'UNKNOWN_SUBMISSION_NEVER_REPLAY'
    with (ROOT/'OWN_JOB_ID').open('x') as f:f.write(found[0]+'\n')
    return found[0]

def main():
    job=None;error=None
    try:
        if MODE=='deploy':job=deploy()
        else:
            assert MODE=='status' and ROOT.resolve(strict=True)==ROOT
            job=(ROOT/'OWN_JOB_ID').read_text().strip()
        assert re.fullmatch('[0-9]+',job)
    except BaseException as e:
        job=None;error=dict(error_type=type(e).__name__,message=str(e)[:1200],server_utc=utc())
        if MODE=='deploy' and OWNED and not (ROOT/'BRIDGE_FAILURE.json').exists():save('BRIDGE_FAILURE.json',error)
    queries={}
    if job is not None:
        queries=dict(squeue=query(['squeue','-h','-j',job,'-o','%i|%T|%N|%R|%Z']),
            sacct=query(['sacct','-X','-S','2026-10-21','-j',job,'--noheader','--parsable2','--format=JobIDRaw,State,ExitCode,NodeList,WorkDir%240,Start,End,Elapsed,AllocCPUS,MaxRSS']),
            scontrol=query(['scontrol','show','job',job,'-o']))
    names=NAMES+(['logs/recovery-'+job+'.out','logs/recovery-'+job+'.err'] if job is not None else [])
    records={};total=0
    for name in names:
        path=ROOT/name
        if not path.exists():records[name]=dict(present=False);continue
        assert path.resolve(strict=True)==path and path.is_file() and not path.is_symlink()
        a=path.stat();assert a.st_size<=2*1024**2
        raw=path.read_bytes();b=path.stat()
        assert (a.st_size,a.st_mtime_ns)==(b.st_size,b.st_mtime_ns) and len(raw)==a.st_size
        total+=len(raw);assert total<=6*1024**2
        records[name]=dict(present=True,bytes=len(raw),sha256=sha(raw),base64=base64.b64encode(raw).decode())
    body=json.dumps(dict(root=str(ROOT),job_id=job,queries=queries,records=records,bridge_error=error,
        server_utc=utc(),seconds=time.monotonic()-START,candidate_only=True,
        scientific_input_accepted=False,prediction_approved=False,
        model_calls=0,automatic_checks_enabled=False),ensure_ascii=False,separators=(',',':')).encode()
    assert len(body)<=8*1024**2
    print('GEOLOGY_RECOVERY_BYTES='+str(len(body)))
    print('GEOLOGY_RECOVERY_SHA256='+sha(body))
    print('GEOLOGY_RECOVERY_ZLIB_BASE64='+base64.b64encode(zlib.compress(body)).decode())
    print('GEOLOGY_RECOVERY_DONE',flush=True)

if __name__=='__main__':main()

GLHYMPS2_SAVED_COMPUTE
