#!/bin/bash
set -euo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -I -B - <<'EVALUATION_STATUS'
import base64, hashlib, json, re, subprocess
from pathlib import Path
root=Path('/data1/home/sunyiq/zhenjiang_update_temporal_eval_20260923_001')
def read(path,maximum):
    if path.is_symlink() or not path.is_file() or not 0 < path.stat().st_size <= maximum:
        raise ValueError('Metadata type or bound differs: '+str(path))
    raw=path.read_bytes()
    return raw,json.loads(raw)
raw,submitted=read(root/'submission/submitted.json',8192)
job=submitted['job_id']
if not re.fullmatch('[1-9][0-9]*',job):raise ValueError('Invalid job')
account=subprocess.run(['sacct','-j',job,'--format=JobIDRaw,State,ExitCode,Elapsed,AllocCPUS,AllocTRES','--parsable2','--noheader'],capture_output=True,text=True,timeout=15,check=False)
out={'job_id':job,'scheduler_returncode':account.returncode,'scheduler':account.stdout[:16000],'files':[]}
for name in ('run/failure.json','run/complete.json','run/result.json','run/selection.json','run/reference_gate.json','run/weights_verified_before_data.json'):
    path=root/name
    if path.exists():
        raw,value=read(path,2000000)
        out['files'].append({'path':str(path),'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest(),'base64':base64.b64encode(raw).decode()})
encoded=json.dumps(out,sort_keys=True)
if len(encoded.encode()) > 790000:raise ValueError('Bounded reply exceeded')
print(encoded)
EVALUATION_STATUS
