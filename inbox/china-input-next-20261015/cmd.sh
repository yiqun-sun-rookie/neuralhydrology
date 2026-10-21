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
MODE='deploy'
PAYLOAD_B64='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'
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
