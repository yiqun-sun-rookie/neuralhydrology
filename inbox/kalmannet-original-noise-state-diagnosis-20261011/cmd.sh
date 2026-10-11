#!/bin/bash
set -eo pipefail
/data1/home/sunyiq/kalmannet_original_noise_multiday_evaluation_20261008_recovery3/runtime/venv/bin/python -X utf8 -B - <<'OWN_FAILED_JOB_READ'
import hashlib,json,subprocess
from pathlib import Path
r=Path('/data1/home/sunyiq/kalmannet_original_noise_internal_state_diagnosis_20261011')
value={'files':{},'scientific_submissions':0,'scientific_retries':0}
for label,command in [('queue',['squeue','--user=sunyiq','--name=noise-state-six','--noheader','--format=%i|%j|%t|%C|%R']),('job',['scontrol','show','job','240064']),('accounting',['sacct','-X','-n','-P','-j','240064','-o','JobID,JobName,State,ExitCode,Submit,Start,End,AllocCPUS,WorkDir,NodeList']),('partition',['scontrol','show','partition','hcpu48y'])]:
    p=subprocess.run(command,capture_output=True,text=True,timeout=45)
    value[label]={'exit_code':p.returncode,'stdout':p.stdout,'stderr':p.stderr}
for path in sorted((r/'logs').glob('*')):
    if path.is_file():
        data=path.read_bytes()
        value['files'][str(path.relative_to(r))]={'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest(),'text':data.decode('utf-8',errors='replace')}
for path in sorted((r/'code').glob('*')):
    if path.is_file():
        data=path.read_bytes()
        value['files'][str(path.relative_to(r))]={'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()}
        if path.name=='submit_state_case.slurm':value['files'][str(path.relative_to(r))]['text']=data.decode('utf-8')
value['case_files']=[str(p.relative_to(r)) for p in (r/'results/cases').rglob('*') if p.is_file()]
print('OWN_FAILED_JOB_READ_JSON='+json.dumps(value),flush=True)
OWN_FAILED_JOB_READ
