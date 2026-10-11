#!/bin/bash
set -eo pipefail
/data1/home/sunyiq/kalmannet_original_noise_multiday_evaluation_20261008_recovery3/runtime/venv/bin/python -X utf8 -B - <<'EXISTING_JOB_TERMINAL_READ'
import json,subprocess,hashlib
from pathlib import Path
r=Path('/data1/home/sunyiq/kalmannet_original_noise_internal_state_diagnosis_20261011_recovery1')
case=r/'results/cases/03340800/attempt_001'
value={'scientific_submissions':0,'scientific_retries':0,'files':{},'sources':{},'submissions':{}}
for label,args in [('queue',['squeue','--user=sunyiq','--name=noise-state-six','--noheader','--format=%i|%j|%t|%C|%R']),('accounting',['sacct','-X','-n','-P','-j','240067','-o','JobID,State,ExitCode,ElapsedRaw,AllocCPUS,NNodes,ReqCPUS,Timelimit,NodeList']),('job',['scontrol','show','job','240067'])]:
    p=subprocess.run(args,capture_output=True,text=True,timeout=45)
    value[label]={'exit_code':p.returncode,'stdout':p.stdout,'stderr':p.stderr}
for p in sorted((r/'submissions').glob('*.json')):value['submissions'][p.name]=p.read_text(encoding='utf-8')
for p in sorted((r/'code').glob('*')):
    if p.is_file():value['sources'][p.name]={'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
if case.exists():
    for p in sorted(case.iterdir()):
        if p.is_file():
            item={'bytes':p.stat().st_size}
            if p.suffix in ('.json','.log'):item['text']=p.read_text(encoding='utf-8')
            value['files'][p.name]=item
for p in sorted((r/'logs').glob('*')):
    if p.is_file():value['files']['job_logs/'+p.name]={'bytes':p.stat().st_size,'text':p.read_text(encoding='utf-8')}
print('EXISTING_JOB_TERMINAL_JSON='+json.dumps(value),flush=True)
EXISTING_JOB_TERMINAL_READ
