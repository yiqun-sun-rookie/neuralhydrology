#!/bin/bash
set -eo pipefail
umask 077
export PYTHONDONTWRITEBYTECODE=1 CUDA_VISIBLE_DEVICES=''
exec timeout --signal=TERM --kill-after=5s 210s /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'WWHYPDA_BRIDGE'
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

ROOT = Path('/data1/home/sunyiq/china_input_completion_hpc_20261015_001/wwhypda_candidate_27888_20261022_transport_repair_v1')
MODE = 'status'
PAYLOAD_B64 = ''
START = time.monotonic()
OWNED = False
NAMES = ['BRIDGE_FAILURE.json','DEPLOYMENT.json','CONTRACT.json','SUBMISSION_STARTED.json',
    'SUBMISSION_RESULT.json','OWN_JOB_ID','COMPUTE_STARTED.json','SOURCE_TRANSPORT.json','SOURCE_TRANSPORT_FAILURE.json','ACQUISITION_RESULT.json',
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
    assert set(payload)=={'wwhypda_repaired_27888_20261022_v1.py','wwhypda_repaired_27888_20261022_v1.sbatch','CONTRACT.json','wwhypda_login_transfer_27888_20261022_v1.py'}
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
    acquired=query(['/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python','-B',str(ROOT/'wwhypda_login_transfer_27888_20261022_v1.py')],130)
    save('ACQUISITION_RESULT.json',acquired)
    assert acquired['exit_code']==0 and not (ROOT/'SOURCE_TRANSPORT_FAILURE.json').exists(),'TRANSFER_FAILED_NO_SUBMIT'
    original=(ROOT/'WWHYPDA_v1.0.0.zip').read_bytes()
    transport=json.loads((ROOT/'SOURCE_TRANSPORT.json').read_bytes())
    assert len(original)==1458542==transport['bytes'] and hashlib.md5(original).hexdigest()=='c2802259cede567e6799b0d6e6e88066'
    assert sha(original)==transport['sha256'] and transport['connection_closed_before_acceptance'] is True
    save('SUBMISSION_STARTED.json',dict(maximum_new_jobs=1,automatic_retries=0,server_utc=utc()))
    submitted=query(['sbatch',str(ROOT/'wwhypda_repaired_27888_20261022_v1.sbatch')],15)
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
    assert len(body)<=4*1024**2 and time.monotonic()-START<200
    print('GEOLOGY_RECOVERY_BYTES='+str(len(body)))
    print('GEOLOGY_RECOVERY_SHA256='+sha(body))
    print('GEOLOGY_RECOVERY_ZLIB_BASE64='+base64.b64encode(zlib.compress(body)).decode())
    print('GEOLOGY_RECOVERY_DONE',flush=True)
    assert time.monotonic()-START<200


if __name__=='__main__':
    main()

WWHYPDA_BRIDGE
