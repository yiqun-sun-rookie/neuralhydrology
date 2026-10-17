#!/bin/bash
set -eo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -u -B -c 'import json,datetime,subprocess,base64,hashlib
from pathlib import Path
r=Path('"'"'/data1/home/sunyiq/knet_camels_hpc_20261012_001/attempts/state_channel_scratch_20261017_001'"'"')
report=dict(queried_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),root_exists=r.exists())
for name in ['"'"'submission_started.json'"'"','"'"'submission.json'"'"','"'"'submission_stdout.txt'"'"']:
 p=r/name
 report[name]=p.read_text() if p.is_file() else None
stage=Path.home()/'"'"'.hpc_mailbox_staging/knet-state-scratch-20261017-001/result_1.txt'"'"'
report['"'"'staged_receipt_exists'"'"']=stage.is_file()
if stage.is_file():
 raw=stage.read_bytes();report['"'"'staged_receipt_sha256'"'"']=hashlib.sha256(raw).hexdigest();report['"'"'staged_receipt_base64'"'"']=base64.b64encode(raw).decode() if len(raw)<100000 else None
report['"'"'receiver_processes'"'"']=subprocess.run(['"'"'pgrep'"'"','"'"'-afu'"'"','"'"'sunyiq'"'"','"'"'hpc_runner_active'"'"'],capture_output=True,text=True,timeout=15).stdout
if (r/'"'"'submission.json'"'"').is_file():
 job=json.loads((r/'"'"'submission.json'"'"').read_text())['"'"'job_id'"'"']
 p=subprocess.run(['"'"'squeue'"'"','"'"'-j'"'"',job,'"'"'-h'"'"','"'"'-o'"'"','"'"'%i|%j|%T|%M|%R'"'"'],capture_output=True,text=True,timeout=20);report['"'"'queue'"'"']=p.stdout;report['"'"'queue_returncode'"'"']=p.returncode
print('"'"'DEPLOYMENT_OBSERVATION_JSON='"'"'+json.dumps(report),flush=True)
'
