#!/bin/bash
set -eo pipefail
cd /data1/home/sunyiq/knet_camels_hpc_20261012_001/attempts/state_channel_diag_20261016_001
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B -c '"""Query the single owned array and package immutable terminal evidence only."""
import sys,json,datetime,subprocess,hashlib,tarfile,io,base64
from pathlib import Path
import safe_io as s
base=Path(sys.argv[1]);job=sys.argv[2];assert job.isdigit()
identity=json.loads(s.read_checked(base/'"'"'submission.json'"'"'));assert identity['"'"'job_id'"'"']==job
accounting=subprocess.run(['"'"'sacct'"'"','"'"'-j'"'"',job,'"'"'--noheader'"'"','"'"'--parsable2'"'"',
    '"'"'--format=JobID,JobName,State,ExitCode,Elapsed,AllocCPUS,Partition,NodeList,Start,End'"'"'],
    capture_output=True,text=True,check=True).stdout.splitlines()
queue=subprocess.run(['"'"'squeue'"'"','"'"'-j'"'"',job,'"'"'-h'"'"','"'"'-o'"'"','"'"'%i|%j|%T|%M|%R'"'"'],capture_output=True,text=True)
terminal_states={'"'"'COMPLETED'"'"','"'"'FAILED'"'"','"'"'CANCELLED'"'"','"'"'TIMEOUT'"'"','"'"'NODE_FAIL'"'"','"'"'OUT_OF_MEMORY'"'"','"'"'PREEMPTED'"'"','"'"'BOOT_FAIL'"'"','"'"'DEADLINE'"'"','"'"'REVOKED'"'"'}
rows={line.split('"'"'|'"'"')[0]:line.split('"'"'|'"'"') for line in accounting}
def terminal_element(index):
    for identifier,fields in rows.items():
        if fields[2].split()[0].rstrip('"'"'+'"'"') not in terminal_states:continue
        if identifier==job+'"'"'_'"'"'+str(index):return True
        if not identifier.startswith(job+'"'"'_['"'"') or not identifier.endswith('"'"']'"'"'):continue
        content=identifier[len(job)+2:-1].split('"'"'%'"'"')[0]
        for part in content.split('"'"','"'"'):
            if '"'"'-'"'"' in part:
                first,last=map(int,part.split('"'"'-'"'"'))
                if first<=index<=last:return True
            elif part.isdigit() and int(part)==index:return True
    return False
terminal=all(terminal_element(i) for i in (0,1))
files={base/'"'"'submission.json'"'"',base/'"'"'submission_started.json'"'"',base/'"'"'execution_authorization.json'"'"',base/'"'"'deployment_manifest.json'"'"'}
progress={};basins=[]
for index,basin in enumerate(['"'"'02092500'"'"','"'"'04105700'"'"']):
    log=base/'"'"'logs'"'"'/('"'"'diagnostic-'"'"'+job+'"'"'_'"'"'+str(index)+'"'"'.out'"'"')
    error=log.with_suffix('"'"'.err'"'"');events=[]
    for p in [log,error]:
        if p.is_file():files.add(p)
    if log.is_file():
        # Live log snapshot is observational; terminal collection uses checked stable reads.
        for line in log.read_text(encoding='"'"'utf-8'"'"',errors='"'"'replace'"'"').splitlines():
            try:event=json.loads(line)
            except ValueError:continue
            if '"'"'event'"'"' in event:
                events.append(event)
                if event['"'"'event'"'"'] in ['"'"'evaluation_complete'"'"','"'"'diagnostic_complete'"'"']:progress[basin]=event
    folder=base/'"'"'runs'"'"'/basin/'"'"'attempt_001'"'"';receipt=folder/'"'"'receipt.json'"'"'
    basins.append(dict(basin=basin,receipt=json.loads(s.read_checked(receipt)) if receipt.is_file() else None,last_events=events[-3:]))
    if folder.is_dir():
        files.update(p for p in folder.iterdir() if p.is_file())
        for sub in ['"'"'evaluations'"'"','"'"'candidate_vectors'"'"']:
            d=folder/sub
            if d.is_dir():files.update(p for p in d.iterdir() if p.is_file())

status=dict(job_id=job,queried_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),identity=identity,
    accounting=accounting,queue=queue.stdout.splitlines(),queue_returncode=queue.returncode,
    all_array_elements_terminal=terminal,basins=basins,progress=list(progress.values()))
print('"'"'JOB_STATUS_JSON='"'"'+json.dumps(status))
if terminal:
    stream=io.BytesIO();manifest=[]
    with tarfile.open(fileobj=stream,mode='"'"'w:gz'"'"') as tar:
        for path in sorted(files):
            raw=s.read_checked(path);name=path.relative_to(base).as_posix()
            item=tarfile.TarInfo(name);item.size=len(raw);item.mode=0o644;item.mtime=0
            tar.addfile(item,io.BytesIO(raw));manifest.append(dict(path=name,bytes=len(raw),sha256=hashlib.sha256(raw).hexdigest()))
        raw=(json.dumps(dict(job_id=job,accounting=accounting,files=manifest,captured_utc=status['"'"'queried_utc'"'"']),indent=2)+'"'"'\n'"'"').encode()
        item=tarfile.TarInfo('"'"'collection_manifest_'"'"'+job+'"'"'.json'"'"');item.size=len(raw);item.mode=0o644;item.mtime=0
        tar.addfile(item,io.BytesIO(raw))
    payload=stream.getvalue()
    print('"'"'ARTIFACT_ARCHIVE_METADATA='"'"'+json.dumps(dict(job_id=job,files=len(files)+1,bytes=len(payload),sha256=hashlib.sha256(payload).hexdigest())))
    print('"'"'ARTIFACT_ARCHIVE_BASE64='"'"'+base64.b64encode(payload).decode())
' /data1/home/sunyiq/knet_camels_hpc_20261012_001/attempts/state_channel_diag_20261016_001 243676
