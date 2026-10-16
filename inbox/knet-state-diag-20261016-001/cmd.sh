#!/bin/bash
set -eo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B -c 'import json,os,datetime,subprocess,sys
from pathlib import Path
import psutil
root=Path('"'"'/data1/home/sunyiq/knet_camels_hpc_20261012_001/attempts/state_channel_diag_20261016_001'"'"')
identity=json.loads((root/'"'"'submission.json'"'"').read_bytes());assert identity['"'"'job_id'"'"']=='"'"'243676'"'"'
queue=subprocess.run(['"'"'squeue'"'"','"'"'-j'"'"','"'"'243676'"'"','"'"'-h'"'"','"'"'-o'"'"','"'"'%i|%T'"'"'],capture_output=True,text=True)
actions=[]
for line in queue.stdout.splitlines():
 fields=line.split('"'"'|'"'"')
 if fields==['"'"'243676_1'"'"','"'"'PENDING'"'"'] or (fields[0].startswith('"'"'243676_['"'"') and fields[1]=='"'"'PENDING'"'"'):
  out=subprocess.run(['"'"'scancel'"'"','"'"'243676_1'"'"'],capture_output=True,text=True)
  actions.append(dict(action='"'"'cancel_owned_unstarted_element1'"'"',returncode=out.returncode,stdout=out.stdout,stderr=out.stderr));assert out.returncode==0
for basin in ['"'"'02092500'"'"','"'"'04105700'"'"']:
 path=root/'"'"'runs'"'"'/basin/'"'"'attempt_001/scientific_started.json'"'"'
 if not path.exists():continue
 record=json.loads(path.read_bytes())
 try:p=psutil.Process(record['"'"'pid'"'"'])
 except psutil.NoSuchProcess:continue
 assert abs(p.create_time()-record['"'"'creation_time'"'"'])<.01
 command=p.cmdline();assert str(root/'"'"'worker.py'"'"') in command
 env=p.environ();assert env['"'"'SLURM_ARRAY_JOB_ID'"'"']=='"'"'243676'"'"'
 p.terminate()
 actions.append(dict(action='"'"'terminate_only_owned_diagnostic_child'"'"',basin=basin,pid=p.pid,creation_time=p.create_time(),command=command))
result=dict(status='"'"'OWNED_TECHNICAL_STOP'"'"',utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),job_id='"'"'243676'"'"',reason='"'"'diagnostic scope dictionary omitted global os/hashlib; no scientific algorithm change'"'"',optimizer_calls=0,actions=actions,prior_queue=queue.stdout)
with (root/'"'"'technical_stop.json'"'"').open('"'"'x'"'"') as h:json.dump(result,h,indent=2)
print('"'"'TECHNICAL_STOP_JSON='"'"'+json.dumps(result))
'
