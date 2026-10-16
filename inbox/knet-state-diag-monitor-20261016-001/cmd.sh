#!/bin/bash
set -eo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -u -B -c 'import json,datetime,subprocess,os
from pathlib import Path
base=Path('"'"'/data1/home/sunyiq/knet_camels_hpc_20261012_001/attempts/state_channel_repaircheck_20261016_001'"'"')
resume=base.parent/'"'"'state_channel_repaircheck_20261016_001_io_resume_001'"'"'
stage=Path('"'"'/data1/home/sunyiq/.hpc_mailbox_staging/knet-state-repaircheck-20261016-001/result_5.txt'"'"')
terminal=json.loads((resume/'"'"'terminal.json'"'"').read_bytes())
assert terminal['"'"'job_id'"'"']=='"'"'244047'"'"' and len(terminal['"'"'results'"'"'])==2
out=dict(nonce='"'"'repair_terminal_probe_20261016_1425'"'"',utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),job_id='"'"'244047'"'"',terminal=terminal,stage_exists=stage.is_file())
if stage.is_file():
 stat=stage.stat()
 with stage.open('"'"'rb'"'"') as f:f.seek(max(0,stat.st_size-1024));tail=f.read().decode(errors='"'"'replace'"'"').splitlines()
 out['"'"'stage'"'"']=dict(bytes=stat.st_size,mtime=stat.st_mtime,complete_headers=[x for x in tail if x.startswith('"'"'###'"'"')])
for key,args in [('"'"'queue'"'"',['"'"'squeue'"'"','"'"'-h'"'"','"'"'-j'"'"','"'"'244047'"'"','"'"'-o'"'"','"'"'%i|%T|%R'"'"']),('"'"'accounting'"'"',['"'"'sacct'"'"','"'"'-n'"'"','"'"'-X'"'"','"'"'-j'"'"','"'"'244047'"'"','"'"'-P'"'"','"'"'--format=JobID,State,ExitCode,Elapsed,NodeList'"'"'])]:
 p=subprocess.run(args,capture_output=True,text=True,timeout=20);out[key]=dict(returncode=p.returncode,stdout=p.stdout,stderr=p.stderr)
p=Path('"'"'/proc/3169/cmdline'"'"');out['"'"'original_receiver'"'"']=p.read_bytes().replace(bytes([0]),b'"'"' '"'"').decode() if p.is_file() else None
print('"'"'REPAIR_TERMINAL_TRANSPORT_PROBE='"'"'+json.dumps(out))
'
