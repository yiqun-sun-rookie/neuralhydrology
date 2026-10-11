#!/bin/bash
set -eo pipefail
/data1/home/sunyiq/kalmannet_original_noise_multiday_evaluation_20261008_recovery3/runtime/venv/bin/python -X utf8 -B - <<'CLOSED_JOB_READ'
import hashlib,json,subprocess,sys,time
from pathlib import Path
import psutil
psutil.Process().cpu_affinity([psutil.Process().cpu_affinity()[0]])
remote=Path('/data1/home/sunyiq/kalmannet_original_noise_internal_state_diagnosis_20261011_recovery1')
folder=remote/'verification/v3/cases/03340800'
report=remote/'results/review/cases/03340800'
job='240096'
submission=json.loads((folder/'submission.json').read_text(encoding='utf-8'))
assert submission['job_id']==job

def call(argv):
    p=subprocess.run(argv,capture_output=True,text=True,timeout=45)
    assert p.returncode==0, {'argv':argv,'code':p.returncode,'stderr':p.stderr}
    return p.stdout
queue=call(['squeue','--user=sunyiq','--noheader','--format=%i|%j|%t'])
queue=[x for x in queue.splitlines() if x.split('|')[0].strip()==job]
account=call(['sacct','-j',job,'--allocations','--noheader','--parsable2','--format=JobIDRaw,State,ExitCode,ElapsedRaw,AllocCPUS,ReqCPUS,NNodes,Timelimit,NodeList'])
rows=[x.rstrip('|').split('|') for x in account.splitlines() if x.split('|')[0].strip()==job]
row=rows[0] if len(rows)==1 else None
terminal=bool(not queue and row and row[1].split()[0] in {'COMPLETED','FAILED','CANCELLED','TIMEOUT','OUT_OF_MEMORY','NODE_FAIL','PREEMPTED','BOOT_FAIL','DEADLINE','REVOKED'})
value={'job_id':job,'queue':queue,'row':row,'accounting_raw':account,'terminal_proven':terminal,'scientific_runs':0,'verification_resubmitted':False,'writes_to_experiment':0,'epoch':time.time(),'files':[],'closed_records':{}}
if terminal:
    for base in (folder,report):
        for p in sorted(base.iterdir()):
            if not p.is_file():continue
            h=hashlib.sha256()
            with p.open('rb') as f:
                for block in iter(lambda:f.read(1048576),b''):h.update(block)
            value['files'].append({'path':p.relative_to(remote).as_posix(),'bytes':p.stat().st_size,'sha256':h.hexdigest()})
    for p in (folder/'supervision.json',folder/'whole_stage_closure.json',folder/'work_failure.json',folder/'guardian_failure.json',report/'checker_execution.json',report/'review.json',report/'saved_check_location.json'):
        if not p.exists():value['closed_records'][p.name]={'missing':True};continue
        try:
            data=json.loads(p.read_text(encoding='utf-8'))
            if p.name=='review.json':data={k:v for k,v in data.items() if k not in ('checks','residuals')};data['check_count']=len(json.loads(p.read_text(encoding='utf-8'))['checks'])
            value['closed_records'][p.name]=data
        except (ValueError,OSError) as error:value['closed_records'][p.name]={'decode_error':repr(error)}
print('REMOTE_JSON='+json.dumps(value),flush=True)
CLOSED_JOB_READ
