#!/usr/bin/env bash
set -eo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PYREMOTE'
import pathlib,subprocess,json,hashlib,tarfile,io,base64,datetime
root=pathlib.Path('/data1/home/sunyiq/knet_camels_hpc_20261012_001/attempts/state_channel_repaircheck_20261016_001')
eng=root.with_name(root.name+'_io_resume_001')
terminal=json.loads((eng/'terminal.json').read_bytes())
assert terminal['job_id']=='244047' and all(x['status']=='COMPLETED' for x in terminal['results'])
queue=subprocess.run(['squeue','-h','-j','244047','-o','%i|%T|%R'],capture_output=True,text=True,check=True).stdout
assert not queue.strip()
accounting=subprocess.run(['sacct','-n','-X','-j','244047','-P','--format=JobID,State,ExitCode,Elapsed,Start,End'],capture_output=True,text=True,check=True).stdout
assert 'COMPLETED|0:0' in accounting
files={}
for p in root.iterdir():
 if p.is_file() and p.suffix in ('.json','.py','.slurm'):files['science/'+p.name]=p
for b in ('02092500','04105700'):
 for attempt in ('attempt_001','attempt_002_io_resume'):
  folder=root/'runs'/b/attempt
  for p in folder.rglob('*'):
   if p.is_file():files['science/'+p.relative_to(root).as_posix()]=p
for p in eng.rglob('*'):
 if p.is_file() and p.suffix in ('.json','.py','.sbatch','.out','.err'):files['engineering/'+p.relative_to(eng).as_posix()]=p
stream=io.BytesIO();manifest=[]
with tarfile.open(fileobj=stream,mode='w:gz') as tar:
 for name,p in sorted(files.items()):
  before=p.stat();raw=p.read_bytes();after=p.stat()
  assert (before.st_size,before.st_mtime_ns)==(after.st_size,after.st_mtime_ns)
  meta=dict(path=name,bytes=len(raw),sha256=hashlib.sha256(raw).hexdigest());manifest.append(meta)
  info=tarfile.TarInfo(name);info.size=len(raw);info.mtime=0;tar.addfile(info,io.BytesIO(raw))
 doc=dict(job_id='244047',original_job_id='244038',queried_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),accounting=accounting,queue=queue,files=manifest,no_model_calls=True)
 raw=json.dumps(doc,indent=2).encode();info=tarfile.TarInfo('collection_manifest.json');info.size=len(raw);info.mtime=0;tar.addfile(info,io.BytesIO(raw))
payload=stream.getvalue()
print('ARCHIVE_METADATA='+json.dumps(dict(bytes=len(payload),sha256=hashlib.sha256(payload).hexdigest(),files=len(manifest),job_id='244047')))
print('ARCHIVE_BASE64='+base64.b64encode(payload).decode())

PYREMOTE
