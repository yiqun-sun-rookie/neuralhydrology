#!/bin/bash
set -eo pipefail
umask 077
export PYTHONDONTWRITEBYTECODE=1 CUDA_VISIBLE_DEVICES=''
exec timeout --signal=TERM --kill-after=5s 110s /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'WWHYPDA_BRIDGE'
"""Deploy one WWHYPDA compute job, or read only that job's saved small records."""
import base64
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import resource
import shutil
import subprocess
import time
import zlib

ROOT = Path('/data1/home/sunyiq/china_input_completion_hpc_20261015_001/wwhypda_candidate_27888_20261022_v1')
MODE = 'deploy'
PAYLOAD_B64 = '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'
START = time.monotonic()
OWNED = False
NAMES = ['BRIDGE_FAILURE.json','DEPLOYMENT.json','CONTRACT.json','SUBMISSION_STARTED.json',
    'SUBMISSION_RESULT.json','OWN_JOB_ID','COMPUTE_STARTED.json','SOURCE_TRANSPORT.json','SOURCE_TRANSPORT_FAILURE.json',
    'ARCHIVE_INVENTORY.json','DATABASE_REPORT.json','COMPUTE_FAILURE.json']


def utc():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def save(name, value):
    raw=(json.dumps(value,ensure_ascii=False,allow_nan=False,indent=2)+'\n').encode()
    assert len(raw)<=2*1024**2
    with (ROOT/name).open('xb') as handle:
        handle.write(raw)


def query(command, seconds=10):
    try:
        result=subprocess.run(command,stdin=subprocess.DEVNULL,capture_output=True,timeout=seconds)
        assert len(result.stdout)<=131072 and len(result.stderr)<=131072
        return dict(command=command,exit_code=result.returncode,stdout=result.stdout.decode('utf8','replace'),
            stderr=result.stderr.decode('utf8','replace'),server_utc=utc())
    except subprocess.TimeoutExpired as error:
        return dict(command=command,exit_code=None,error='TIMEOUT_UNKNOWN',
            stdout=(error.stdout or b'').decode('utf8','replace')[:131072],
            stderr=(error.stderr or b'').decode('utf8','replace')[:131072],server_utc=utc())


def deploy():
    global OWNED
    assert not ROOT.exists(),'OWN_ROOT_EXISTS_NEVER_REPLAY'
    assert ROOT.parent.resolve(strict=True)==ROOT.parent and shutil.disk_usage(ROOT.parent).free>=256*1024**2
    payload=json.loads(zlib.decompress(base64.b64decode(PAYLOAD_B64,validate=True)))
    assert set(payload)=={'wwhypda_candidate_27888_20261022_v2.py','wwhypda_candidate_27888_20261022_v2.sbatch','CONTRACT.json'}
    ROOT.mkdir(mode=0o700);OWNED=True;(ROOT/'logs').mkdir()
    files={}
    for name,row in payload.items():
        raw=base64.b64decode(row['base64'],validate=True)
        assert len(raw)==row['bytes']<=131072 and sha(raw)==row['sha256']
        with (ROOT/name).open('xb') as handle:
            handle.write(raw)
        files[name]=dict(bytes=len(raw),sha256=sha(raw))
    contract=json.loads((ROOT/'CONTRACT.json').read_bytes())
    assert contract['root']==str(ROOT) and contract['maximum_new_jobs']==1 and contract['source_archive_bytes']==1458542
    save('DEPLOYMENT.json',dict(files=files,server_utc=utc(),science_on_login_node=False))
    save('SUBMISSION_STARTED.json',dict(maximum_new_jobs=1,automatic_retries=0,server_utc=utc()))
    submitted=query(['sbatch',str(ROOT/'wwhypda_candidate_27888_20261022_v2.sbatch')],15)
    save('SUBMISSION_RESULT.json',submitted)
    found=re.findall(r'^Submitted batch job ([0-9]+)\s*$',submitted['stdout'],re.M)
    assert submitted['exit_code']==0 and len(found)==1,'UNKNOWN_SUBMISSION_NEVER_REPLAY'
    with (ROOT/'OWN_JOB_ID').open('x') as handle:
        handle.write(found[0]+'\n')
    return found[0]


def main():
    resource.setrlimit(resource.RLIMIT_AS,(256*1024**2,resource.getrlimit(resource.RLIMIT_AS)[1]))
    job=None;error=None
    try:
        if MODE=='deploy':
            job=deploy()
        else:
            assert MODE=='status' and ROOT.resolve(strict=True)==ROOT
            job=(ROOT/'OWN_JOB_ID').read_text().strip()
        assert re.fullmatch('[0-9]+',job)
    except BaseException as caught:
        job=None;error=dict(error_type=type(caught).__name__,message=str(caught)[:1400],server_utc=utc())
        if MODE=='deploy' and OWNED and not (ROOT/'BRIDGE_FAILURE.json').exists():
            save('BRIDGE_FAILURE.json',error)
    queries={}
    if job is not None:
        queries=dict(squeue=query(['squeue','-h','-j',job,'-o','%i|%T|%N|%R|%Z']),
            sacct=query(['sacct','-X','-S','2026-10-22','-j',job,'--noheader','--parsable2',
                '--format=JobIDRaw,State,ExitCode,NodeList,WorkDir%240,Start,End,Elapsed,AllocCPUS,MaxRSS']),
            scontrol=query(['scontrol','show','job',job,'-o']))
    names=NAMES+(['logs/audit-'+job+'.out','logs/audit-'+job+'.err'] if job is not None else [])
    records={};total=0
    for name in names:
        path=ROOT/name
        if not path.exists():
            records[name]=dict(present=False);continue
        assert path.resolve(strict=True)==path and path.is_file() and not path.is_symlink()
        before=path.stat();assert before.st_size<=2*1024**2
        raw=path.read_bytes();after=path.stat()
        assert (before.st_size,before.st_mtime_ns)==(after.st_size,after.st_mtime_ns) and len(raw)==before.st_size
        total+=len(raw);assert total<=2500000
        records[name]=dict(present=True,bytes=len(raw),sha256=sha(raw),base64=base64.b64encode(raw).decode())
    value=dict(kind='WWHYPDA_CANDIDATE',root=str(ROOT),job_id=job,queries=queries,records=records,
        bridge_error=error,server_utc=utc(),seconds=time.monotonic()-START,
        maximum_new_jobs=int(MODE=='deploy'),candidate_only=True,scientific_input_accepted=False,
        prediction_approved=False,model_calls=0,automatic_checks_enabled=False)
    body=json.dumps(value,ensure_ascii=False,allow_nan=False,separators=(',',':')).encode()
    assert len(body)<=4*1024**2 and time.monotonic()-START<100
    print('GEOLOGY_RECOVERY_BYTES='+str(len(body)))
    print('GEOLOGY_RECOVERY_SHA256='+sha(body))
    print('GEOLOGY_RECOVERY_ZLIB_BASE64='+base64.b64encode(zlib.compress(body)).decode())
    print('GEOLOGY_RECOVERY_DONE',flush=True)
    assert time.monotonic()-START<100


if __name__=='__main__':
    main()

WWHYPDA_BRIDGE
