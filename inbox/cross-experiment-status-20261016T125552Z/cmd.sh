#!/usr/bin/env bash
set -u
python3 - <<'PYREMOTE'
import subprocess,json,datetime,time
now=lambda:datetime.datetime.now(datetime.timezone.utc).isoformat()
def run(args):
 try:
  p=subprocess.run(args,stdout=subprocess.PIPE,stderr=subprocess.PIPE,universal_newlines=True,timeout=15);return dict(returncode=p.returncode,stdout=p.stdout,stderr=p.stderr)
 except Exception as e:return dict(error_type=type(e).__name__)
a=dict(started_utc=now(),no_submissions=True,no_job_mutations=True)
a['queue']=run(['squeue','-r','-h','-u','sunyiq','-o','%i|%j|%T|%r|%N'])
a['accounting']=run(['sacct','-n','-X','-j','242759,244039,244010,244024,244042,244043','--format=JobIDRaw,State,ExitCode,Elapsed,NodeList','-P'])
a['cpu_first']={j:run(['sstat','-n','-j',j+'.batch','--format=JobID,AveCPU,AveRSS','-P']) for j in ['242759','244039']}
time.sleep(7)
a['cpu_second']={j:run(['sstat','-n','-j',j+'.batch','--format=JobID,AveCPU,AveRSS','-P']) for j in ['242759','244039']}
a['finished_utc']=now()
print('ACTUAL_EXECUTION_JSON_BEGIN');print(json.dumps(a));print('ACTUAL_EXECUTION_JSON_END')
PYREMOTE
