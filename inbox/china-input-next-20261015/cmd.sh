#!/bin/bash
set -eo pipefail
umask 077
export PYTHONDONTWRITEBYTECODE=1 CUDA_VISIBLE_DEVICES=''
exec timeout --signal=TERM --kill-after=5s 90s /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'GLHYMPS2_HPC_BYTES'
"""One detached bounded byte controller, then fixed metadata-only status reads."""
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

ROOT=Path('/data1/home/sunyiq/china_input_completion_hpc_20261015_001/glhymps2_hpc_byte_stage_20261021_v2')
PYTHON='/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python'
CONTROL='glhymps2_login_bytes_control_20261021_v2.py'
MODE='status'
PAYLOAD_B64=''
NAMES=['BRIDGE_FAILURE.json','DEPLOYMENT.json','PREDECESSORS.json','LAUNCH.json',
       'CONTROL_STARTED.json','WORKER_LAUNCH.json','CONTROL_RESULT.json','CONTROL_FAILURE.json','CONTROL_FINAL.json',
       'BYTE_STARTED.json','BYTE_RESULT.json','BYTE_FAILURE.json','FETCH_STARTED.json','FETCH_RECORDS.json',
       'ROUTE_USED.json','ARCHIVE_IDENTITY.json','TRANSFER_PROGRESS.json',
       'worker.stdout','worker.stderr','supervisor.stdout','supervisor.stderr']
START=time.monotonic()
OWNED=False


def utc():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def save(name,value):
    raw=(json.dumps(value,ensure_ascii=False,allow_nan=False,indent=2)+'\n').encode()
    assert len(raw)<=2*1024**2
    with (ROOT/name).open('xb') as stream:
        stream.write(raw)


def query(args):
    p=subprocess.run(args,stdin=subprocess.DEVNULL,capture_output=True,timeout=9)
    assert len(p.stdout)<=131072 and len(p.stderr)<=131072
    return dict(command=args,exit_code=p.returncode,stdout=p.stdout.decode(errors='replace'),
                stderr=p.stderr.decode(errors='replace'),server_utc=utc())


def proc(pid,expected=None):
    base=Path('/proc')/str(pid)
    value=(base/'stat').read_text()
    fields=value[value.rfind(')')+2:].split()
    boot=Path('/proc/sys/kernel/random/boot_id').read_text().strip()
    if expected is not None and (int(fields[19])!=expected['start_ticks'] or boot!=expected['boot_id']):
        return dict(identity_mismatch=True)
    args=(base/'cmdline').read_bytes().split(b'\0')
    if args and args[-1]==b'':args.pop()
    return dict(pid=pid,start_ticks=int(fields[19]),state=fields[0],
                cwd=str((base/'cwd').resolve(strict=True)),command=[a.decode() for a in args],
                boot_id=boot,pgid=os.getpgid(pid))


def deploy():
    global OWNED
    assert not ROOT.exists() and ROOT.parent.resolve(strict=True)==ROOT.parent
    assert shutil.disk_usage(ROOT.parent).free>=32*1024**3
    raw=zlib.decompress(base64.b64decode(PAYLOAD_B64,validate=True));assert len(raw)<512*1024
    payload=json.loads(raw)
    required={'CONTRACT.json','DNS_ROUTE.json','ENTRY_TABLE.json','glhymps2_fixed_route_20261021_v1.py',
              'glhymps2_login_bytes_20261021_v2.py',CONTROL}
    assert set(payload)==required
    contract=json.loads(base64.b64decode(payload['CONTRACT.json']['base64'],validate=True))
    assert contract['root']==str(ROOT) and contract['login_bytes_only'] is True
    predecessors=[]
    assert [r['job'] for r in contract['predecessors']]==['245942','245964']
    for row in contract['predecessors']:
        p=Path(row['root']);assert p.resolve(strict=True)==p
        for name,desc in row['records'].items():
            path=p/name;assert path.resolve(strict=True)==path and not path.is_symlink()
            body=path.read_bytes();assert len(body)==desc['bytes'] and sha(body)==desc['sha256']
        f=json.loads((p/'FETCH_RECORDS.json').read_bytes())
        assert f['body_bytes']==0 and len(f['requests'])==1
        assert not any((p/n).exists() for n in ('GLHYMPS2_original.zip','GLHYMPS2_original.zip.partial','ARCHIVE_IDENTITY.json'))
        q=query(['sacct','-X','-S','2026-10-21','-j',row['job'],'--noheader','--parsable2',
                 '--format=JobIDRaw,State,ExitCode,WorkDir%240'])
        lines=[s.strip().split('|') for s in q['stdout'].splitlines() if s.strip()]
        assert q['exit_code']==0 and len(lines)==1 and lines[0][:4]==[row['job'],'FAILED','1:0',str(p)]
        predecessors.append(q)
    ROOT.mkdir(mode=0o700);OWNED=True
    files={}
    for name,row in payload.items():
        body=base64.b64decode(row['base64'],validate=True)
        assert len(body)==row['bytes']<=131072 and sha(body)==row['sha256']
        with (ROOT/name).open('xb') as out:out.write(body)
        files[name]=dict(bytes=len(body),sha256=sha(body))
    save('DEPLOYMENT.json',dict(files=files,new_jobs=0,scientific_decodes=0,server_utc=utc()))
    save('PREDECESSORS.json',dict(failed_jobs=predecessors,old_archives_present=False))
    timeout=shutil.which('timeout');assert timeout and Path(timeout).is_absolute()
    args=[timeout,'--signal=TERM','--kill-after=25s','1890s',PYTHON,'-B',str(ROOT/CONTROL)]
    with (ROOT/'supervisor.stdout').open('xb') as out,(ROOT/'supervisor.stderr').open('xb') as err:
        child=subprocess.Popen(args,cwd=ROOT,env=dict(os.environ,CUDA_VISIBLE_DEVICES='',PYTHONDONTWRITEBYTECODE='1'),
            stdin=subprocess.DEVNULL,stdout=out,stderr=err,start_new_session=True)
    # Popen is unique; even a quick completed failure never permits another launch.
    identity=None
    try:identity=proc(child.pid)
    except (FileNotFoundError,ProcessLookupError):pass
    if identity is not None:
        assert identity['command']==args and identity['cwd']==str(ROOT) and identity['pgid']==child.pid
    save('LAUNCH.json',dict(pid=child.pid,args=args,identity=identity,server_utc=utc(),
                           no_replay=True,new_jobs=0,maximum_byte_stages=1))
    time.sleep(.5)


def main():
    error=None
    try:
        if MODE=='deploy':deploy()
        else:assert MODE=='status' and ROOT.resolve(strict=True)==ROOT
    except BaseException as e:
        error=dict(type=type(e).__name__,message=str(e)[:1200],server_utc=utc())
        if OWNED and not (ROOT/'BRIDGE_FAILURE.json').exists():save('BRIDGE_FAILURE.json',error)
    process=dict(identity_verified=False,alive=False)
    if (ROOT/'LAUNCH.json').is_file():
        launch=json.loads((ROOT/'LAUNCH.json').read_bytes())
        try:
            before=launch['identity']
            if before is None:
                process.update(initial_identity_unknown=True)
            else:
                current=proc(launch['pid'],expected=before)
                if current.get('identity_mismatch'):
                    process.update(identity_mismatch=True)
                else:
                    same=all(current[k]==before[k] for k in ('pid','start_ticks','cwd','command','boot_id','pgid'))
                    if same:process=dict(identity_verified=True,alive=current['state']!='Z',actual=current)
                    else:process.update(identity_mismatch=True)
        except (FileNotFoundError,ProcessLookupError):
            process.update(pid_absent=True)
    stats={}
    for name in ('GLHYMPS2_original.zip.partial','GLHYMPS2_original.zip'):
        p=ROOT/name
        if p.exists():
            assert p.resolve(strict=True)==p and not p.is_symlink() and p.is_file()
            s=p.stat();assert s.st_size<=2595563951
            stats[name]=dict(bytes=s.st_size,mtime_ns=s.st_mtime_ns,stat_only=True)
    records={};total=0
    for name in NAMES:
        p=ROOT/name
        if not p.exists():records[name]=dict(present=False);continue
        assert p.resolve(strict=True)==p and not p.is_symlink() and p.is_file()
        with p.open('rb') as stream:
            before=os.fstat(stream.fileno());assert before.st_size<=2*1024**2
            raw=stream.read(2*1024**2+1);after=os.fstat(stream.fileno())
        if (before.st_size,before.st_mtime_ns)!=(after.st_size,after.st_mtime_ns) or len(raw)!=before.st_size:
            records[name]=dict(present=False,exists=True,unstable_current_record=True)
            continue
        total+=len(raw);assert total<=6*1024**2
        records[name]=dict(present=True,bytes=len(raw),sha256=sha(raw),base64=base64.b64encode(raw).decode())
    value=dict(kind='GLHYMPS2_HPC_BYTE_STAGE',root=str(ROOT),process=process,files_stat=stats,records=records,
               bridge_error=error,server_utc=utc(),seconds=time.monotonic()-START,
               new_jobs=0,scientific_decodes=0,model_calls=0,automatic_checks_enabled=False,
               scientific_input_accepted=False,prediction_approved=False)
    body=json.dumps(value,ensure_ascii=False,separators=(',',':')).encode();assert len(body)<=8*1024**2
    print('GEOLOGY_RECOVERY_BYTES='+str(len(body)))
    print('GEOLOGY_RECOVERY_SHA256='+sha(body))
    print('GEOLOGY_RECOVERY_ZLIB_BASE64='+base64.b64encode(zlib.compress(body)).decode())
    print('GEOLOGY_RECOVERY_DONE',flush=True)


if __name__=='__main__':main()

GLHYMPS2_HPC_BYTES
