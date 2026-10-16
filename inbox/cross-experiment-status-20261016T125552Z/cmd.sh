#!/usr/bin/env bash
# sequence=1; read-only cross-project execution inspection, no submission
set -u
python3 - <<'PYREMOTE'
import subprocess,json,datetime,time,pathlib,socket,os
now=lambda:datetime.datetime.now(datetime.timezone.utc).isoformat()
def run(args,timeout=30):
 try:
  p=subprocess.run(args,stdout=subprocess.PIPE,stderr=subprocess.PIPE,universal_newlines=True,timeout=timeout)
  return dict(argv=args,returncode=p.returncode,stdout=p.stdout,stderr=p.stderr)
 except Exception as e:return dict(argv=args,error_type=type(e).__name__)
ids=['236706','236707','237928','243692','244010','244024','244015','242770','243369','242751','242752','242753','242754','243113','242305','241629','243069','242474','228327','241336','241337','241344']
a=dict(kind='ACTUAL_SCHEDULER_INSPECTION',started_utc=now(),host=socket.gethostname(),uid=os.getuid(),no_submissions=True,no_job_mutations=True)
a['queue']=run(['squeue','-r','-h','-u','sunyiq','-o','%i|%j|%T|%r|%N|%C|%Z|%o|%E'])
a['accounting']=run(['sacct','-n','-X','-j',','.join(ids),'--format=JobIDRaw,JobName%65,State,ExitCode,Start,End,Elapsed,NodeList,WorkDir%150','-P'])
a['registered_details']={j:run(['scontrol','-o','show','job',j]) for j in ['236706','236707','237928','244010','244024','244015','242770']}
a['progress_metadata']={}
roots=[pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261006_002'),pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261008_recovery_002'),pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261016_recovery_006'),pathlib.Path('/data1/home/sunyiq/zhenjiang_training_covariance_failure_006_20261016_001'),pathlib.Path('/data1/home/sunyiq/china_input_completion_hpc_20261015_001/hydroatlas_extract_headers_v1')]
for root in roots:
 paths=list(root.glob('records/*/progress.json'))+[root/'control/CONTROL.json',root/'CONTROL.json',root/'control/progress.json',root/'control/status.json']
 for p in paths:
  if p.is_file() and p.stat().st_size<200000:
   try:a['progress_metadata'][str(p)]=dict(mtime=p.stat().st_mtime,value=json.loads(p.read_text()))
   except Exception as e:a['progress_metadata'][str(p)]=dict(error_type=type(e).__name__)
live=[]
for line in a['queue'].get('stdout','').splitlines():
 cells=line.split('|')
 if len(cells)>2 and cells[2]=='RUNNING':live.append(cells[0])
live=sorted(set(live))[:30]
a['running_statistics_first']={j:run(['sstat','-n','-j',j+'.batch','--format=JobID,AveCPU,AveRSS,MaxRSS','-P'],15) for j in live}
a['first_statistics_utc']=now()
if live:time.sleep(7)
a['running_statistics_second']={j:run(['sstat','-n','-j',j+'.batch','--format=JobID,AveCPU,AveRSS,MaxRSS','-P'],15) for j in live}
a['finished_utc']=now()
print('ACTUAL_EXECUTION_JSON_BEGIN')
print(json.dumps(a,sort_keys=True))
print('ACTUAL_EXECUTION_JSON_END')
PYREMOTE
