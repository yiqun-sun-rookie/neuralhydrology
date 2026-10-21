#!/bin/bash
set -eo pipefail
umask 077
export PYTHONDONTWRITEBYTECODE=1 CUDA_VISIBLE_DEVICES=''
exec timeout --signal=TERM --kill-after=5s 300s /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'GAP_SOURCE_SUPPORT'
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

ROOT=Path('/data1/home/sunyiq/china_input_completion_hpc_20261015_001/gap27888_source_support_20261021_v1')
MODE='status'
PAYLOAD_B64=''
START=time.monotonic()
OWNED=False
NAMES=['BRIDGE_FAILURE.json', 'DEPLOYMENT.json', 'SUBMISSION_STARTED.json', 'SUBMISSION_RESULT.json', 'OWN_JOB_ID', 'FETCH_STARTED.json', 'GIT_INIT_RESULT.json', 'FETCH_RESULT.json', 'PRIVATE_TREE_VERIFICATION.json', 'COMPUTE_STARTED.json', 'AUDIT_RESULT.json', 'COMPUTE_FAILURE.json', 'ORIGINAL_BOUNDARY.json', 'TARGET_IDENTITY.json', 'SOURCE_SUPPORT_RELATION.json', 'MASK_CROSS_SOURCE.json', 'SOURCE_UNCHANGED.json', 'HYDROATLAS_SUPPORT.json', 'MASK_SUPPORT.json', 'DEPTH_SUPPORT.json', 'DEM_SUPPORT.json', 'GLIM_SUPPORT.json', 'PERMEABILITY_SUPPORT.json', 'POROSITY_SUPPORT.json']

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
    assert ROOT.parent.resolve(strict=True)==ROOT.parent and shutil.disk_usage(ROOT.parent).free>=2*1024**3
    raw=zlib.decompress(base64.b64decode(PAYLOAD_B64,validate=True));assert len(raw)<512*1024
    payload=json.loads(raw)
    assert set(payload)=={'gap27888_source_support_20261021_v1.py', 'gap27888_source_support_20261021_v1.sbatch', 'CONTRACT.json'}
    ROOT.mkdir(mode=0o700);OWNED=True;(ROOT/'logs').mkdir()
    deployed={}
    for name,row in payload.items():
        body=base64.b64decode(row['base64'],validate=True)
        assert len(body)==row['bytes']<=131072 and sha(body)==row['sha256']
        with (ROOT/name).open('xb') as f:f.write(body)
        deployed[name]=dict(bytes=len(body),sha256=sha(body))
    c=json.loads((ROOT/'CONTRACT.json').read_bytes());assert c['root']==str(ROOT)
    fetch=c['byte_transport']
    if fetch is not None:
        assert fetch['repository']=='yiqun-sun-rookie/forecast_system_lite'
        assert fetch['branch']=='codex/china-boundary-27888-20261021-v2' and re.fullmatch('[0-9a-f]{40}',fetch['commit'])
        save('FETCH_STARTED.json',dict(private_commit=fetch['commit'],maximum_attempts=1,maximum_seconds=180,scientific_values_parsed=0))
        bare=ROOT/'private_git'
        init=query(['git','init','--bare',str(bare)],10);save('GIT_INIT_RESULT.json',init);assert init['exit_code']==0
        env=dict(os.environ,GIT_TERMINAL_PROMPT='0',GIT_ASKPASS='/bin/false',SSH_ASKPASS='/bin/false',
            GIT_SSH_COMMAND='ssh -oBatchMode=yes -oStrictHostKeyChecking=yes -oConnectTimeout=20 -oConnectionAttempts=1')
        command=['timeout','--signal=TERM','--kill-after=3s','180s','git','-c','gc.auto=0','-c','pack.windowMemory=64m','-c','pack.threads=1',
            '--git-dir='+str(bare),'fetch','--quiet','--no-tags','--depth=1','git@github.com:'+fetch['repository']+'.git','refs/heads/'+fetch['branch']]
        process=subprocess.run(command,stdin=subprocess.DEVNULL,capture_output=True,timeout=188,env=env,start_new_session=True)
        assert len(process.stdout)<=131072 and len(process.stderr)<=131072
        save('FETCH_RESULT.json',dict(exit_code=process.returncode,stdout=process.stdout.decode(errors='replace'),stderr=process.stderr.decode(errors='replace')))
        assert process.returncode==0,'PRIVATE_FETCH_FAILED_NEVER_REPLAY'
        head=query(['git','--git-dir='+str(bare),'rev-parse','FETCH_HEAD']);assert head['exit_code']==0 and head['stdout'].strip()==fetch['commit']
        tree=query(['git','--git-dir='+str(bare),'ls-tree',fetch['commit']]);assert tree['exit_code']==0
        expected={x['name']:x['git_oid'] for x in fetch['objects']};assert len(expected)==1 and set(expected)=={'0_catchment_boundary.zip'}
        actual={}
        for line in tree['stdout'].splitlines():
            mode,kind,rest=line.split(' ',2);git_oid,name=rest.split('\t',1)
            assert mode=='100644' and kind=='blob' and name not in actual;actual[name]=git_oid
        assert actual==expected
        dest=Path(c['boundary_archive']['path']);assert dest==ROOT/'0_catchment_boundary.zip'
        with dest.open('xb') as stream:
            copied=subprocess.run(['git','--git-dir='+str(bare),'show',fetch['commit']+':0_catchment_boundary.zip'],stdin=subprocess.DEVNULL,stdout=stream,stderr=subprocess.PIPE,timeout=30)
        assert copied.returncode==0 and len(copied.stderr)<=131072
        body=dest.read_bytes();assert len(body)==c['boundary_archive']['bytes']==18108565 and sha(body)==c['boundary_archive']['sha256']
        assert sum(p.stat().st_size for p in bare.rglob('*') if p.is_file())<=64*1024**2
        save('PRIVATE_TREE_VERIFICATION.json',dict(private_commit=fetch['commit'],objects=actual,archive_bytes=len(body),archive_sha256=sha(body),scientific_values_parsed=0))
    else:
        source=Path(c['boundary_archive']['path']);assert source.resolve(strict=True)==source and source.is_file() and source.stat().st_size==18108565
    save('DEPLOYMENT.json',dict(files=deployed,original_downloads=0,private_fetches=int(fetch is not None),scientific_values_parsed=0,server_utc=utc()))
    save('SUBMISSION_STARTED.json',dict(max_new_jobs=1,automatic_retries=0,server_utc=utc()))
    sub=query(['sbatch',str(ROOT/'gap27888_source_support_20261021_v1.sbatch')],15);save('SUBMISSION_RESULT.json',sub)
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

GAP_SOURCE_SUPPORT
