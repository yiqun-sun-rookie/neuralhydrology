#!/bin/bash
set -eo pipefail
cd /data1/home/sunyiq/knet_camels_hpc_20261012_001/attempts/state_channel_repaircheck_20261016_001
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -u -B -c '"""Read-only terminal collection of original failure and already completed I/O continuation."""
import sys,json,datetime,subprocess,hashlib,tarfile,io,base64
from pathlib import Path
import safe_io as s
base=Path('"'"'/data1/home/sunyiq/knet_camels_hpc_20261012_001/attempts/state_channel_repaircheck_20261016_001'"'"')
resume=base.parent/'"'"'state_channel_repaircheck_20261016_001_io_resume_001'"'"'
original=json.loads(s.read_checked(base/'"'"'submission.json'"'"'))
identity=json.loads(s.read_checked(resume/'"'"'submission.json'"'"'))
assert original['"'"'job_id'"'"']=='"'"'244038'"'"' and identity['"'"'job_id'"'"']=='"'"'244047'"'"'
assert original['"'"'archive_sha256'"'"']=='"'"'e49fb454a7761d319a8b7405fc31b0b36c3f46881a87a6fb0234c15f1021f429'"'"'
assert identity['"'"'payload_sha256'"'"']=='"'"'76adb76b9b402bf5ca909d28921515286983494c9043d5c8f50480d0761ab4d3'"'"'
accounting=subprocess.run(['"'"'sacct'"'"','"'"'-X'"'"','"'"'-j'"'"','"'"'244038,244047'"'"','"'"'-n'"'"','"'"'-P'"'"','"'"'--format=JobID,State,ExitCode,Elapsed,NodeList'"'"'],capture_output=True,text=True,check=True)
queue=subprocess.run(['"'"'squeue'"'"','"'"'-j'"'"','"'"'244038,244047'"'"','"'"'-h'"'"','"'"'-o'"'"','"'"'%i|%j|%T|%M|%R'"'"'],capture_output=True,text=True,check=True)
assert not queue.stdout.strip(),'"'"'Collection requires both original and recovery jobs terminal'"'"'
rows=[x.split('"'"'|'"'"') for x in accounting.stdout.splitlines() if x]
assert any(x[0]=='"'"'244047_0'"'"' and x[1]=='"'"'COMPLETED'"'"' and x[2]=='"'"'0:0'"'"' for x in rows)
for i in (0,1):assert any(x[0]=='"'"'244038_'"'"'+str(i) and x[1]=='"'"'FAILED'"'"' for x in rows)
terminal=json.loads(s.read_checked(resume/'"'"'terminal.json'"'"'));assert terminal['"'"'job_id'"'"']=='"'"'244047'"'"' and terminal['"'"'no_optimizer_updates'"'"']
assert len(terminal['"'"'results'"'"'])==2 and all(x['"'"'status'"'"']=='"'"'COMPLETED'"'"' and x['"'"'total_optimizer_calls'"'"']==0 for x in terminal['"'"'results'"'"'])
files={}
def add(path,name):
    assert path.is_file() and name not in files
    files[name]=path
for name in ['"'"'submission.json'"'"','"'"'submission_started.json'"'"','"'"'execution_authorization.json'"'"','"'"'deployment_manifest.json'"'"']:
    add(base/name,name)
for row in json.loads(s.read_checked(base/'"'"'deployment_manifest.json'"'"'))['"'"'files'"'"']:
    if row['"'"'path'"'"'] not in files:add(base/row['"'"'path'"'"'],row['"'"'path'"'"'])
for name in ['"'"'submission.json'"'"','"'"'submission_started.json'"'"','"'"'resume_worker.py'"'"','"'"'resume_controller.py'"'"','"'"'resume.sbatch'"'"','"'"'recovery_contract.json'"'"','"'"'controller_started.json'"'"','"'"'terminal.json'"'"']:
    add(resume/name,'"'"'io_resume_001/'"'"'+name)
for p in (resume/'"'"'cache_manifests'"'"').iterdir():
    if p.is_file():add(p,'"'"'io_resume_001/cache_manifests/'"'"'+p.name)
for p in resume.glob('"'"'resume-*.out'"'"'):add(p,'"'"'io_resume_001/'"'"'+p.name)
for p in resume.glob('"'"'resume-*.err'"'"'):add(p,'"'"'io_resume_001/'"'"'+p.name)
for basin in ['"'"'02092500'"'"','"'"'04105700'"'"']:
    for attempt in ['"'"'attempt_001'"'"','"'"'attempt_002_io_resume'"'"']:
        folder=base/'"'"'runs'"'"'/basin/attempt
        for p in folder.iterdir():
            if p.is_file():add(p,p.relative_to(base).as_posix())
        for name in ['"'"'evaluations'"'"','"'"'candidate_vectors'"'"']:
            d=folder/name
            if d.is_dir():
                for p in d.iterdir():
                    if p.is_file():add(p,p.relative_to(base).as_posix())
for p in (base/'"'"'logs'"'"').iterdir():
    if p.is_file():add(p,p.relative_to(base).as_posix())
status=dict(job_id='"'"'244047'"'"',original_job_id='"'"'244038'"'"',original_identity=original,recovery_identity=identity,
    queried_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),all_array_elements_terminal=True,
    accounting=accounting.stdout.splitlines(),queue=queue.stdout.splitlines(),terminal=terminal,
    scientific_reexecution=False)
print('"'"'JOB_STATUS_JSON='"'"'+json.dumps(status),flush=True)
stream=io.BytesIO();manifest=[]
with tarfile.open(fileobj=stream,mode='"'"'w:gz'"'"') as tar:
    for name,path in sorted(files.items()):
        raw=s.read_checked(path);item=tarfile.TarInfo(name);item.size=len(raw);item.mode=0o644;item.mtime=0
        tar.addfile(item,io.BytesIO(raw));manifest.append(dict(path=name,bytes=len(raw),sha256=hashlib.sha256(raw).hexdigest()))
    raw=(json.dumps(dict(job_id='"'"'244047'"'"',original_job_id='"'"'244038'"'"',accounting=status['"'"'accounting'"'"'],
        files=manifest,captured_utc=status['"'"'queried_utc'"'"']),indent=2)+'"'"'\n'"'"').encode()
    item=tarfile.TarInfo('"'"'collection_manifest_244047.json'"'"');item.size=len(raw);item.mode=0o644;item.mtime=0
    tar.addfile(item,io.BytesIO(raw))
payload=stream.getvalue()
print('"'"'ARTIFACT_ARCHIVE_METADATA='"'"'+json.dumps(dict(job_id='"'"'244047'"'"',files=len(files)+1,bytes=len(payload),sha256=hashlib.sha256(payload).hexdigest())),flush=True)
print('"'"'ARTIFACT_ARCHIVE_BASE64='"'"'+base64.b64encode(payload).decode(),flush=True)
'
