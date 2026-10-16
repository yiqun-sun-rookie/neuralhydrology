#!/usr/bin/env bash
set -eo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -u -B - <<'PYREMOTE'
import subprocess,json,datetime,time,re,pathlib
job='244047';root=pathlib.Path('/data1/home/sunyiq/knet_camels_hpc_20261012_001/attempts/state_channel_repaircheck_20261016_001_io_resume_001')
def run(args):
 try:
  p=subprocess.run(args,capture_output=True,text=True,timeout=20);return dict(returncode=p.returncode,stdout=p.stdout,stderr=p.stderr)
 except Exception as e:return dict(error_type=type(e).__name__)
now=lambda:datetime.datetime.now(datetime.timezone.utc).isoformat()
out=dict(job_id=job,root=str(root),queried_utc=now(),no_job_mutations=True)
out['queue']=run(['squeue','-r','-h','-j',job+',244038','-o','%i|%j|%T|%r|%N'])
out['accounting']=run(['sacct','-n','-X','-j',job+',244038','--format=JobID,State,ExitCode,Elapsed,NodeList','-P'])
out['scheduler']=run(['scontrol','-o','show','job',job])
out['documents']={}
old=root.parent/'state_channel_repaircheck_20261016_001'
out['original_failure_tails']={}
for b in ('02092500','04105700'):
 p=old/'runs'/b/'attempt_001/stdout.log'
 if p.is_file():out['original_failure_tails'][b]=p.read_bytes()[-3500:].decode(errors='replace')
for p in [root/'controller_started.json',root/'terminal.json']+[old/'runs'/b/'attempt_002_io_resume'/name for b in ('02092500','04105700') for name in ('resume_binding.json','scientific_started.json','receipt.json')]:
 if p.is_file() and p.stat().st_size<100000:out['documents'][str(p)]=json.loads(p.read_text())
logs=sorted(root.glob('resume-*.out'))
out['current_job_log_tail']=logs[-1].read_bytes()[-12000:].decode(errors='replace') if logs else ''
physical=re.search(r'JobId=(\d+).*?JobState=RUNNING',out['scheduler'].get('stdout',''))
if physical:
 args=['sstat','-n','-j',physical.group(1)+'.batch','--format=JobID,AveCPU,AveRSS','-P']
 out['cpu_first']=run(args);time.sleep(7);out['cpu_second']=run(args)
out['finished_utc']=now();print('RECOVERY_STATUS_JSON='+json.dumps(out))

PYREMOTE
