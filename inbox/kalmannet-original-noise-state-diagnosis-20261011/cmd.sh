#!/bin/bash
set -eo pipefail
/data1/home/sunyiq/kalmannet_original_noise_multiday_evaluation_20261008_recovery3/runtime/venv/bin/python -X utf8 -B - <<'READ_ONLY_SUBMISSION_DIAGNOSIS'
import json,hashlib,subprocess,base64,time
from pathlib import Path
root=Path('/data1/home/sunyiq/kalmannet_original_noise_internal_state_diagnosis_20261011_recovery1')
folder=root/'verification/v6/cases/06431500'
report=root/'results/review/cases/06431500'
assert folder.resolve().is_relative_to(root.resolve())
def file(p):
 if not p.exists():return {'path':str(p.relative_to(root)),'exists':False}
 assert p.is_file() and not p.is_symlink() and p.stat().st_size < 1048576
 b=p.read_bytes()
 v={'path':str(p.relative_to(root)),'exists':True,'bytes':len(b),'sha256':hashlib.sha256(b).hexdigest(),'base64':base64.b64encode(b).decode('ascii')}
 try:v['json']=json.loads(b)
 except (ValueError,UnicodeDecodeError):v['text']=b.decode('utf-8',errors='replace')
 return v
def command(argv):
 p=subprocess.run(argv,capture_output=True,text=True,timeout=30)
 assert p.returncode==0, {'argv':argv,'exit_code':p.returncode,'stdout':p.stdout,'stderr':p.stderr}
 return {'argv':argv,'exit_code':p.returncode,'stdout':p.stdout,'stderr':p.stderr}
files=[file(folder/n) for n in ('submit_dispatch.json','submit_response.json','submission.json','whole_stage_closure.json','supervisor_receipt.json','guardian_launch.json')]
files.extend(file(root/n) for n in ('verification/v6/manifest.json','verification/v6/check_saved.slurm','results/cases/06431500/attempt_001/scheduler_receipt.json','results/cases/06431500/attempt_001/raw_manifest.json'))
listing=[]
for directory in (folder,report):
 if directory.exists():
  candidates=sorted(directory.rglob('*'));assert len(candidates)<200
  for p in candidates:
   if p.is_file():listing.append({'path':str(p.relative_to(root)),'bytes':p.stat().st_size,'mtime':p.stat().st_mtime})
queue=command(['squeue','--user=sunyiq','--noheader','--format=%i|%j|%t|%C|%N|%V'])
accounting=command(['sacct','--user=sunyiq','--name=noise-state-six,noise-state-verify','--starttime=2026-10-11T00:00:00','--allocations','--noheader','--parsable2','--format=JobIDRaw,JobName,State,ExitCode,ElapsedRaw,AllocCPUS,NNodes,Timelimit,NodeList,Submit,Start,End'])
print('REMOTE_JSON='+json.dumps({'status':'READ_ONLY_SAVED_SUBMISSION_DIAGNOSIS','utc_epoch':time.time(),'remote_files':files,'folder_listing':listing,'queue':queue,'accounting':accounting,'scientific_executions':0,'saved_array_submissions':0,'remote_writes':0}),flush=True)
READ_ONLY_SUBMISSION_DIAGNOSIS
