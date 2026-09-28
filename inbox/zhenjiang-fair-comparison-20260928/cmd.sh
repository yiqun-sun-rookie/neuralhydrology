#!/bin/bash
set -euo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -I -B - <<'ZJ_FAIR_FAILURE'
from pathlib import Path
import hashlib,json,subprocess
root=Path('/data1/home/sunyiq/zhenjiang_fair_comparison_20260928_001')
job='229355'
def read(name,limit=16384):
    path=root/name
    if not path.exists(): return None
    if path.is_symlink() or not path.is_file() or path.stat().st_size>limit:
        raise ValueError('failure evidence file type or size differs: '+name)
    raw=path.read_bytes()
    return {'sha256':hashlib.sha256(raw).hexdigest(),'text':raw.decode(errors='replace')}
account=subprocess.run(['sacct','-j',job,'-n','-P','--format=JobID,State,ExitCode,Elapsed,AllocTRES'],capture_output=True,text=True,timeout=15,check=False)
if len(account.stdout)+len(account.stderr)>8192: raise ValueError('scheduler output exceeds bound')
print(json.dumps({'job_id':job,'submission_attempt':read('submission/attempt.json'),
    'submitted':read('submission/submitted.json'),
    'scheduler_reply':read('submission/scheduler_reply.json'),
    'preflight_result':read('preflight/result.json'),
    'preflight_failure':read('preflight/failure.json'),
    'training_attempt':read('run/separate_available/attempt.json'),
    'training_failure':read('run/separate_available/failure.json'),
    'job_log':read('slurm/job_'+job+'.log'),
    'accounting':{'returncode':account.returncode,'stdout':account.stdout,'stderr':account.stderr}},sort_keys=True))
ZJ_FAIR_FAILURE
