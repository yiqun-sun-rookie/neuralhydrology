#!/bin/bash
set -eo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -u -B -c 'import json,datetime,subprocess,socket
report=dict(queried_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),query_host=socket.gethostname(),transport_nonce='"'"'19f14d475edb4cd7aeae2a6d41120082'"'"',read_only=True,scientific_job_id='"'"'244229'"'"',array_job_id='"'"'244228'"'"')
for name,cmd in [('"'"'node'"'"',['"'"'scontrol'"'"','"'"'show'"'"','"'"'node'"'"','"'"'ngu104'"'"']),('"'"'job'"'"',['"'"'scontrol'"'"','"'"'show'"'"','"'"'job'"'"','"'"'244229'"'"','"'"'-o'"'"']),('"'"'usage'"'"',['"'"'sstat'"'"','"'"'-j'"'"','"'"'244229.batch'"'"','"'"'--noheader'"'"','"'"'--format=JobID,AveCPU,MaxRSS'"'"','"'"'-P'"'"']),('"'"'node_queue'"'"',['"'"'squeue'"'"','"'"'-w'"'"','"'"'ngu104'"'"','"'"'-h'"'"','"'"'-o'"'"','"'"'%i|%T|%C|%M|%R'"'"']),('"'"'partition'"'"',['"'"'scontrol'"'"','"'"'show'"'"','"'"'partition'"'"','"'"'hgpu4'"'"'])]:
 try:
  p=subprocess.run(cmd,capture_output=True,text=True,timeout=20);report[name]=dict(returncode=p.returncode,stdout=p.stdout[-12000:],stderr=p.stderr[-1500:])
 except Exception as e:report[name]=dict(error=type(e).__name__+'"'"': '"'"'+str(e))
print('"'"'RESOURCE_DIAG_JSON='"'"'+json.dumps(report),flush=True)
'
