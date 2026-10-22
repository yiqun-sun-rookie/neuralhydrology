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
MODE = 'deploy'
PAYLOAD_B64 = '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'
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
