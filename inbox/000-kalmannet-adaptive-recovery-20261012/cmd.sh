#!/bin/bash
sequence=11
umask 077
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -I -S -B - <<'CHECK'
import os,json,base64,hashlib,datetime,subprocess
from pathlib import Path
assert os.getuid()==os.geteuid()==2272
R=Path('/data1/home/sunyiq/kalmannet_cpu_remaining_fourteen_prefix_20261012_007')
r={'read_only':True,'scientific_submissions':0,'observed_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'files':{},'queries':[]}
paths=[R/'root_receipts/submission_receipt.json',R/'output/task_internal_candidate.json']
for i in (25,26,27,28):
 paths.extend([R/f'output/case_{i:03d}/formal/result.json',R/f'output/case_{i:03d}/formal/learned_covariance_reconstruction.json',R/f'output/case_{i:03d}/technical_summary.json'])
 if (R/'output/runtime').is_dir():paths.extend(sorted((R/'output/runtime').glob(f'case_{i:03d}*')))
for p in paths:
 if p.is_file() and not p.is_symlink():
  b=p.read_bytes();r['files'][str(p)]={'bytes':len(b),'sha256':hashlib.sha256(b).hexdigest()}
  if len(b)<=1024**2:r['files'][str(p)]['base64']=base64.b64encode(b).decode()
 else:r['files'][str(p)]={'exists':p.exists()}
job=None
if (R/'root_receipts/submission_receipt.json').is_file():job=json.loads((R/'root_receipts/submission_receipt.json').read_bytes())['job_id']
queries=[['scontrol','show','job','241249','--oneliner']]
if job:queries.extend([['scontrol','show','job',job,'--oneliner'],['sacct','-j',job,'--parsable2','--noheader','--format=JobIDRaw,JobName,User,UID,Partition,Submit,Start,End,ElapsedRaw,AllocCPUS,AllocTRES,ReqTRES,State,ExitCode,NodeList,WorkDir,TimelimitRaw,Comment,CPUTimeRAW,TotalCPU']])
for a in queries:
 try:
  q=subprocess.run(a,capture_output=True,stdin=subprocess.DEVNULL,timeout=20,env={**os.environ,'TZ':'UTC','LC_ALL':'C'})
  r['queries'].append({'argv':a,'returncode':q.returncode,'stdout':q.stdout.decode(errors='replace'),'stderr':q.stderr.decode(errors='replace')})
 except BaseException as e:r['queries'].append({'argv':a,'error_type':type(e).__name__})
print(json.dumps(r,sort_keys=True))
CHECK
