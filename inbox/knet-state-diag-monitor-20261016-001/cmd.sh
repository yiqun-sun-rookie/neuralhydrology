#!/bin/bash
set -eo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -u -B -c 'from pathlib import Path
import json,datetime,subprocess,hashlib,socket,re
h=Path.home();report=dict(queried_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),query_host=socket.gethostname(),transport_nonce='"'"'b3ecc1c0a7bf409b9e705ef6333c7cf1'"'"')
for p in [h/'"'"'.hpc_mailbox_staging/knet-state-scratch-20261017-001/result_15.txt'"'"',h/'"'"'hpc_mailbox/outbox/knet-state-scratch-20261017-001/result_15.txt'"'"',h/'"'"'hpc_mailbox/.git/index.lock'"'"',h/'"'"'.hpc_mailbox_pushlock'"'"']:
 row=dict(exists=p.exists())
 if p.exists():
  st=p.stat();row.update(bytes=st.st_size,mtime=st.st_mtime)
  if p.is_file() and st.st_size<2000000:row['"'"'sha256'"'"']=hashlib.sha256(p.read_bytes()).hexdigest()
 report[str(p)]=row
for label,cmd,cwd in [('"'"'repo_heads'"'"',['"'"'git'"'"','"'"'rev-parse'"'"','"'"'HEAD'"'"','"'"'refs/remotes/origin/hpc-mailbox'"'"'],str(h/'"'"'hpc_mailbox'"'"')),('"'"'process_metadata'"'"',['"'"'ps'"'"','"'"'-u'"'"','"'"'sunyiq'"'"','"'"'-o'"'"','"'"'pid,ppid,stat,etime,comm'"'"'],None)]:
 try:
  p=subprocess.run(cmd,cwd=cwd,capture_output=True,text=True,timeout=20);report[label]=dict(returncode=p.returncode,stdout=p.stdout[-12000:],stderr=p.stderr[-2000:])
 except Exception as e:report[label]=dict(error=type(e).__name__+'"'"': '"'"'+str(e))
p=h/'"'"'knet_camels_hpc_20261012_001/attempts/020_snow_training_20261014_001/original_receiver_recovery/20261014T113723Z_2923/live_runner2.log'"'"'
if p.is_file():
 with p.open('"'"'rb'"'"') as f:f.seek(max(0,p.stat().st_size-12000));report['"'"'receiver_log_tail'"'"']=f.read().decode(errors='"'"'replace'"'"')
print('"'"'TRANSPORT_DIAG_JSON='"'"'+json.dumps(report),flush=True)
'
