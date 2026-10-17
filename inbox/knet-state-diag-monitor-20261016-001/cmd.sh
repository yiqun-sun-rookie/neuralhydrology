#!/bin/bash
set -eo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -u -B -c 'import json,datetime,subprocess,hashlib,socket
from pathlib import Path
r=Path('"'"'/data1/home/sunyiq/knet_camels_hpc_20261012_001/attempts/state_channel_scratch_20261017_001'"'"')
report=dict(queried_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),query_host=socket.gethostname(),transport_nonce='"'"'d3299131d2b44e348c7f1deb72d56478'"'"')
paths=[Path.home()/'"'"'.hpc_mailbox_staging/knet-state-scratch-20261017-001/result_13.txt'"'"',Path.home()/'"'"'hpc_mailbox/outbox/knet-state-scratch-20261017-001/result_13.txt'"'"',Path.home()/'"'"'hpc_mailbox/.git/index.lock'"'"',Path.home()/'"'"'.hpc_mailbox_pushlock'"'"']
for p in paths:
 row=dict(exists=p.exists())
 if p.exists():
  st=p.stat();row.update(bytes=st.st_size,mtime=st.st_mtime,is_file=p.is_file())
  if p.is_file() and p.stat().st_size<2000000:row['"'"'sha256'"'"']=hashlib.sha256(p.read_bytes()).hexdigest()
 report[str(p)]=row
for label,cmd in [('"'"'receiver_processes'"'"',['"'"'pgrep'"'"','"'"'-afu'"'"','"'"'sunyiq'"'"','"'"'hpc_runner_active'"'"']),('"'"'repo_heads'"'"',['"'"'git'"'"','"'"'-C'"'"',str(Path.home()/'"'"'hpc_mailbox'"'"'),'"'"'rev-parse'"'"','"'"'HEAD'"'"','"'"'refs/remotes/origin/hpc-mailbox'"'"'])]:
 try:
  p=subprocess.run(cmd,capture_output=True,text=True,timeout=15);report[label]=dict(returncode=p.returncode,stdout=p.stdout[-4000:],stderr=p.stderr[-1000:])
 except Exception as e:report[label]=dict(error=type(e).__name__+'"'"': '"'"'+str(e))
print('"'"'TRANSPORT_DIAG_JSON='"'"'+json.dumps(report),flush=True)
p=subprocess.run(['"'"'/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python'"'"','"'"'-u'"'"','"'"'-B'"'"',str(r/'"'"'query_monitor.py'"'"'),str(r),'"'"'244228'"'"','"'"'d3299131d2b44e348c7f1deb72d56478'"'"'],capture_output=True,text=True,timeout=100)
print(p.stdout,flush=True)
print('"'"'QUERY_RETURN_CODE='"'"'+str(p.returncode),flush=True)
if p.stderr:print('"'"'QUERY_STDERR='"'"'+p.stderr[-4000:],flush=True)
'
