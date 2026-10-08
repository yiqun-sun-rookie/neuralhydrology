#!/bin/bash
set -eo pipefail
/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python -X utf8 -B - <<'READ_ONLY_SUBMISSION_DIAGNOSIS'

import hashlib, json, os, subprocess
from pathlib import Path
ROOT = Path('/data1/home/sunyiq/kalmannet_original_noise_multiday_evaluation_20261008_recovery4')
CHANNEL = 'kalmannet-original-noise-formal-period-recovery-20261008'
out = {'scientific_submissions':0,'cancellations':0,'file_mutations':0,'installations':0,'staging':[],'records':{},'processes':[]}
for number in (1,2):
    p=Path('/data1/home/sunyiq/.hpc_mailbox_staging')/CHANNEL/('result_'+str(number)+'.txt')
    item={'sequence':number,'path':str(p),'exists':p.exists()}
    if p.exists():
        raw=p.read_bytes();lines=raw.decode('utf-8',errors='replace').splitlines()
        markers=[x for x in lines if x.startswith(('### channel=','### started=','### exit_code=','### finished='))]
        item.update(bytes=len(raw),sha256=hashlib.sha256(raw).hexdigest(),markers=markers,
                    complete=sum(x.startswith('### exit_code=') for x in lines)==1 and sum(x.startswith('### finished=') for x in lines)==1)
    out['staging'].append(item)
for name in ('submissions/batch_000_100.json','submissions/batch_000_100_intent.json','submissions/batch_000_100_uncertain.json','results/control/batch_000_100_launch.json','results/control/batch_000_100_execution_receipt.json','results/basins/01078000.json','results/basins/01123000.json'):
    p=ROOT/name
    item={'exists':p.exists()}
    if p.exists():
        if p.stat().st_size>131072: raise RuntimeError('Known small diagnosis record exceeds limit: '+name)
        raw=p.read_bytes();item.update(bytes=len(raw),sha256=hashlib.sha256(raw).hexdigest(),record=json.loads(raw))
    out['records'][name]=item
ps=subprocess.run(['ps','-u','sunyiq','-o','pid=,ppid=,etimes=,comm='],check=True,capture_output=True,text=True,timeout=30).stdout
processes=[]
for line in ps.splitlines():
    fields=line.split(None,3)
    if len(fields)!=4:continue
    pid,ppid,age,comm=fields
    labels=[]
    try:
        argv=(Path('/proc')/pid/'cmdline').read_bytes().replace(b'\0',b' ').decode('utf-8',errors='replace')
        if CHANNEL in argv:labels.append('production_channel')
        if str(ROOT) in argv:labels.append('science_directory')
        if '.hpc_runner_active' in argv:labels.append('mailbox_runner')
        for fd in ('1','2'):
            try:
                if CHANNEL in os.readlink('/proc/'+pid+'/fd/'+fd):labels.append('production_channel_output')
            except OSError:pass
    except OSError:pass
    if labels or comm in ('git','ssh','curl'):
        processes.append({'pid':int(pid),'ppid':int(ppid),'elapsed_seconds':int(age),'comm':comm,'relevance':sorted(set(labels))})
out['processes']=processes
q=subprocess.run(['/data1/home/sunyiq/kalmannet_original_noise_multiday_evaluation_20261008_recovery3/runtime/venv/bin/python','-X','utf8','-B',str(ROOT/'code/remote.py'),'status'],check=True,capture_output=True,text=True,timeout=180)
rows=[x[len('STATUS_JSON='):] for x in q.stdout.splitlines() if x.startswith('STATUS_JSON=')]
if len(rows)!=1:raise RuntimeError('Expected one read-only status result')
out['actual_status']=json.loads(rows[0])
print('SUBMISSION_DIAGNOSIS_JSON='+json.dumps(out),flush=True)

READ_ONLY_SUBMISSION_DIAGNOSIS
