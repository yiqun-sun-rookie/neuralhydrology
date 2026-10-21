#!/bin/bash
set -eo pipefail
umask 077
export PYTHONDONTWRITEBYTECODE=1 CUDA_VISIBLE_DEVICES=''
exec timeout --signal=TERM --kill-after=5s 120s /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'SOURCE_OVERLAY'
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

ROOT=Path('/data1/home/sunyiq/china_input_completion_hpc_20261015_001/glim_three_source_overlay_20261021_v1')
MODE='status'
PAYLOAD_B64=''
START=time.monotonic()
OWNED=False
NAMES=['BRIDGE_FAILURE.json', 'DEPLOYMENT.json', 'SUBMISSION_STARTED.json', 'SUBMISSION_RESULT.json', 'OWN_JOB_ID', 'COMPUTE_STARTED.json', 'AUDIT_RESULT.json', 'COMPUTE_FAILURE.json', 'SOURCE_VERIFIED.json', 'SOURCE_UNCHANGED.json', 'LAYER_INVENTORY.json', 'SOURCE_METADATA.json', 'CATEGORY_DICTIONARIES.json', 'member_25878.json', 'member_25878_features.json', 'member_25878_issues.json', 'member_27888.json', 'member_27888_features.json', 'member_27888_issues.json', 'member_37153.json', 'member_37153_features.json', 'member_37153_issues.json']

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
    assert ROOT.parent.resolve(strict=True)==ROOT.parent and shutil.disk_usage(ROOT.parent).free>=16*1024**3
    raw=zlib.decompress(base64.b64decode(PAYLOAD_B64,validate=True));assert len(raw)<512*1024
    payload=json.loads(raw)
    assert set(payload)=={'glim_three_source_overlay_20261021_v1.sbatch', 'glim_three_source_overlay_20261021_v1.py', 'CONTRACT.json', 'native_glhymps_audit_20261020_v4.py'}
    ROOT.mkdir(mode=0o700);OWNED=True;(ROOT/'logs').mkdir()
    deployed={}
    for name,row in payload.items():
        body=base64.b64decode(row['base64'],validate=True)
        assert len(body)==row['bytes']<=131072 and sha(body)==row['sha256']
        with (ROOT/name).open('xb') as f:f.write(body)
        deployed[name]=dict(bytes=len(body),sha256=sha(body))
    c=json.loads((ROOT/'CONTRACT.json').read_bytes());assert c['root']==str(ROOT)
    source=Path(c['glim_container']);assert source.resolve(strict=True)==source and source.is_dir()
    save('DEPLOYMENT.json',dict(files=deployed,original_downloads=0,private_fetches=0,scientific_values_parsed=0,server_utc=utc()))
    save('SUBMISSION_STARTED.json',dict(max_new_jobs=1,automatic_retries=0,server_utc=utc()))
    sub=query(['sbatch',str(ROOT/'glim_three_source_overlay_20261021_v1.sbatch')],15);save('SUBMISSION_RESULT.json',sub)
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
        server_utc=utc(),seconds=time.monotonic()-START,candidate_only=True,declared_length_accepted=False,
        original_archive_accepted=False,scientific_input_accepted=False,prediction_approved=False,
        model_calls=0,automatic_checks_enabled=False),ensure_ascii=False,separators=(',',':')).encode()
    assert len(body)<=8*1024**2
    print('GEOLOGY_RECOVERY_BYTES='+str(len(body)))
    print('GEOLOGY_RECOVERY_SHA256='+sha(body))
    print('GEOLOGY_RECOVERY_ZLIB_BASE64='+base64.b64encode(zlib.compress(body)).decode())
    print('GEOLOGY_RECOVERY_DONE',flush=True)

if __name__=='__main__':main()

SOURCE_OVERLAY
