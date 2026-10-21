#!/bin/bash
set -eo pipefail
umask 077
export PYTHONDONTWRITEBYTECODE=1 CUDA_VISIBLE_DEVICES=''
exec timeout --signal=TERM --kill-after=5s 120s /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'GLIM_CANDIDATE'
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

ROOT=Path('/data1/home/sunyiq/china_input_completion_hpc_20261015_001/glim_received_body_diagnostic_20261021_v1')
MODE='status'
PAYLOAD_B64=''
START=time.monotonic()
OWNED=False
NAMES=['BRIDGE_FAILURE.json','FETCH_STARTED.json','GIT_INIT_RESULT.json','FETCH_RESULT.json',
       'PRIVATE_TREE_VERIFICATION.json','DEPLOYMENT.json','SUBMISSION_STARTED.json',
       'SUBMISSION_RESULT.json','OWN_JOB_ID','COMPUTE_STARTED.json','ASSEMBLED_CANDIDATE.json',
       'ZIP_DIRECTORY.json','EXTRACTED_MEMBERS.json','ZIP_INTEGRITY.json','LAYER_INVENTORY.json',
       'FIRST32_ATTRIBUTES.json','AUDIT_RESULT.json','COMPUTE_FAILURE.json']

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
    assert ROOT.parent.resolve(strict=True)==ROOT.parent and shutil.disk_usage(ROOT.parent).free>=8*1024**3
    payload=json.loads(zlib.decompress(base64.b64decode(PAYLOAD_B64,validate=True)))
    assert set(payload)=={'CONTRACT.json','glim_candidate_integrity_20261021_v2.py','glim_candidate_integrity_20261021_v2.sbatch'}
    ROOT.mkdir(mode=0o700);OWNED=True;(ROOT/'logs').mkdir();(ROOT/'transport').mkdir()
    deployed={}
    for name,row in payload.items():
        raw=base64.b64decode(row['base64'],validate=True)
        assert len(raw)==row['bytes']<=131072 and sha(raw)==row['sha256']
        with (ROOT/name).open('xb') as f:f.write(raw)
        assert sha((ROOT/name).read_bytes())==row['sha256']
        deployed[name]=dict(bytes=len(raw),sha256=sha(raw))
    c=json.loads((ROOT/'CONTRACT.json').read_bytes())
    assert c['root']==str(ROOT) and c['private_repository']=='yiqun-sun-rookie/forecast_system_lite'
    assert c['private_branch']=='codex/glim-received-body-20261021-v2' and re.fullmatch('[0-9a-f]{40}',c['private_commit'])
    assert c['candidate_only'] is True and c['original_archive_accepted'] is False and c['declared_length_accepted'] is False
    assert c['archive_bytes']==1138679164 and len(c['parts'])==46 and len(c['objects'])==47
    save('FETCH_STARTED.json',dict(private_commit=c['private_commit'],maximum_attempts=1,maximum_seconds=1800,scientific_values_parsed=0,server_utc=utc()))
    bare=ROOT/'transport/private_git'
    initialized=query(['git','init','--bare',str(bare)],10);save('GIT_INIT_RESULT.json',initialized)
    assert initialized['exit_code']==0
    env=dict(os.environ,GIT_TERMINAL_PROMPT='0',GIT_ASKPASS='/bin/false',SSH_ASKPASS='/bin/false',
             GIT_SSH_COMMAND='ssh -oBatchMode=yes -oStrictHostKeyChecking=yes -oConnectTimeout=30 -oConnectionAttempts=1')
    command=['timeout','--signal=TERM','--kill-after=3s','1800s','git','-c','pack.windowMemory=64m','-c','pack.threads=1',
             '--git-dir='+str(bare),'fetch','--quiet','--no-tags','--depth=1',
             'git@github.com:'+c['private_repository']+'.git','refs/heads/'+c['private_branch']]
    # GNU timeout owns the entire Git/SSH process group; no application retry.
    fetched=subprocess.run(command,stdin=subprocess.DEVNULL,capture_output=True,timeout=1808,env=env,start_new_session=True)
    assert len(fetched.stdout)<=131072 and len(fetched.stderr)<=131072
    save('FETCH_RESULT.json',dict(exit_code=fetched.returncode,stdout=fetched.stdout.decode(errors='replace'),stderr=fetched.stderr.decode(errors='replace'),server_utc=utc()))
    assert fetched.returncode==0,'PRIVATE_FETCH_FAILED_NEVER_REPLAY'
    head=query(['git','--git-dir='+str(bare),'rev-parse','FETCH_HEAD'])
    assert head['exit_code']==0 and head['stdout'].strip()==c['private_commit']
    tree=query(['git','--git-dir='+str(bare),'ls-tree',c['private_commit']])
    assert tree['exit_code']==0
    expected={r['name']:r['git_oid'] for r in c['objects']}
    actual={}
    for line in tree['stdout'].splitlines():
        mode,kind,rest=line.split(' ',2);oid,name=rest.split('\t',1)
        assert mode=='100644' and kind=='blob' and name not in actual
        actual[name]=oid
    assert actual==expected,'EXACT_47_ROOT_BLOBS'
    metadata=query(['git','--git-dir='+str(bare),'show',c['private_commit']+':PARTS.json'])
    raw=metadata['stdout'].encode()
    assert metadata['exit_code']==0 and len(raw)==c['objects'][-1]['bytes'] and sha(raw)==c['objects'][-1]['sha256']
    parts=json.loads(raw)
    assert parts['parts']==c['parts'] and parts['bytes']==c['archive_bytes'] and parts['sha256']==c['archive_sha256']
    assert parts['candidate_only'] is True and parts['original_archive_accepted'] is False and parts['declared_length_accepted'] is False
    gitbytes=sum(f.stat().st_size for f in bare.rglob('*') if f.is_file())
    assert gitbytes<=2*1024**3
    save('PRIVATE_TREE_VERIFICATION.json',dict(private_commit=c['private_commit'],objects=actual,parts_manifest_sha256=sha(raw),candidate_only=True))
    save('DEPLOYMENT.json',dict(files=deployed,private_commit=c['private_commit'],private_git_bytes=gitbytes,scientific_values_parsed=0,server_utc=utc()))
    save('SUBMISSION_STARTED.json',dict(max_new_jobs=1,automatic_retries=0,server_utc=utc()))
    sub=query(['sbatch',str(ROOT/'glim_candidate_integrity_20261021_v2.sbatch')],15);save('SUBMISSION_RESULT.json',sub)
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
    names=NAMES+(['logs/glim-'+job+'.out','logs/glim-'+job+'.err'] if job is not None else [])
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
    print('GLIM_CANDIDATE_BYTES='+str(len(body)))
    print('GLIM_CANDIDATE_SHA256='+sha(body))
    print('GLIM_CANDIDATE_ZLIB_BASE64='+base64.b64encode(zlib.compress(body)).decode())
    print('GLIM_CANDIDATE_DONE',flush=True)

if __name__=='__main__':main()

GLIM_CANDIDATE
