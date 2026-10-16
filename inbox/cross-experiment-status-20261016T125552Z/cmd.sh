#!/usr/bin/env bash
# seq=2; only metadata reads, no job or science mutation
set -u
python3 - <<'PYREMOTE'
import subprocess,json,datetime,time,pathlib,socket,os,re
now=lambda:datetime.datetime.now(datetime.timezone.utc).isoformat()
def run(args,timeout=25):
 try:
  p=subprocess.run(args,stdout=subprocess.PIPE,stderr=subprocess.PIPE,universal_newlines=True,timeout=timeout)
  return dict(argv=args,returncode=p.returncode,stdout=p.stdout,stderr=p.stderr)
 except Exception as e:return dict(argv=args,error_type=type(e).__name__)
a=dict(started_utc=now(),host=socket.gethostname(),no_submissions=True,no_job_mutations=True)
a['queue']=run(['squeue','-r','-h','-u','sunyiq','-o','%i|%j|%T|%r|%N|%C|%Z|%o|%E'])
ids=['244038','243725','244010','244015','244024','215428','215429','242758','243042','242770']
a['accounting']=run(['sacct','-n','-X','-j',','.join(ids),'--format=JobIDRaw,JobID%25,JobName%55,State,ExitCode,Start,End,Elapsed,NodeList,WorkDir%140','-P'])
a['job_details']={j:run(['scontrol','-o','show','job',j]) for j in ['244038','244010','242758_0','241691','215429']}
a['metadata']={}
roots=[('/data1/home/sunyiq/china_input_completion_hpc_20261015_001/hydroatlas_extract_headers_v1',['CONTROL_STARTED.json','CONTROL_RESULT.json','CONTROL_FAILURE.json','HYDROATLAS_ACQUISITION_FAILURE.json']),('/data1/home/sunyiq/knet_camels_hpc_20261012_001/attempts/state_channel_repaircheck_20261016_001',['CONTROL.json','progress.json','status.json','run_status.json','terminal.json'])]
for root,names in roots:
 p=pathlib.Path(root)
 a['metadata'][root]={'top_files':[dict(name=f.name,bytes=f.stat().st_size,mtime=f.stat().st_mtime) for f in list(p.iterdir())[:80] if f.is_file()] if p.is_dir() else []}
 for name in names:
  f=p/name
  if f.is_file() and f.stat().st_size<=65000:
   try:a['metadata'][root][name]=json.loads(f.read_text())
   except Exception as e:a['metadata'][root][name]={'error':type(e).__name__}
live=[]
for line in a['queue'].get('stdout','').splitlines():
 cells=line.split('|')
 if len(cells)>2 and cells[2]=='RUNNING':live.append(cells[0])
a['statistics_first']={j:run(['sstat','-a','-n','-j',j,'--format=JobID,AveCPU,AveRSS,MaxRSS','-P'],12) for j in live[:15]}
time.sleep(7)
a['statistics_second']={j:run(['sstat','-a','-n','-j',j,'--format=JobID,AveCPU,AveRSS,MaxRSS','-P'],12) for j in live[:15]}
a['finished_utc']=now()
print('ACTUAL_EXECUTION_JSON_BEGIN');print(json.dumps(a,sort_keys=True));print('ACTUAL_EXECUTION_JSON_END')
PYREMOTE
