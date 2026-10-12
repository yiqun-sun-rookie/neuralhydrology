#!/bin/bash
sequence=6
umask 077
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -I -S -B - <<'CHECK'
import os,json,base64,hashlib,datetime,subprocess
from pathlib import Path
R=Path('/data1/home/sunyiq/kalmannet_cpu_remaining_fourteen_prefix_20261012_005')
r={'read_only':True,'scientific_submissions':0,'observed_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'files':{},'queries':[],'formal_results':[]}
assert os.getuid()==os.geteuid()==2272
paths=[R/'root_receipts/submission_receipt.json',R/'output/task_internal_candidate.json',R/'metadata/preparation_receipt.json']
if (R/'logs').is_dir():paths.extend(sorted((R/'logs').glob('slurm-241303.*')))
if (R/'output').is_dir():
 paths.extend(sorted((R/'output').glob('*.json')))
 for p in sorted((R/'output').glob('case_*/formal/result.json')):r['formal_results'].append({'path':str(p),'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
for p in dict.fromkeys(paths):
 if p.is_file() and not p.is_symlink():
  b=p.read_bytes();r['files'][str(p)]={'bytes':len(b),'sha256':hashlib.sha256(b).hexdigest()}
  if len(b)<=1024**2:r['files'][str(p)]['base64']=base64.b64encode(b).decode()
 else:r['files'][str(p)]={'exists':p.exists()}
for a in [['scontrol','show','job','241303','--oneliner'],['sacct','-j','241303','--parsable2','--noheader','--format=JobIDRaw,JobName,User,UID,Partition,Submit,Start,End,ElapsedRaw,AllocCPUS,AllocTRES,ReqTRES,State,ExitCode,NodeList,WorkDir,TimelimitRaw,Comment,CPUTimeRAW,TotalCPU'],['scontrol','show','job','241249','--oneliner']]:
 try:
  q=subprocess.run(a,capture_output=True,stdin=subprocess.DEVNULL,timeout=20,env={**os.environ,'TZ':'UTC','LC_ALL':'C'});r['queries'].append({'argv':a,'returncode':q.returncode,'stdout':q.stdout.decode(errors='replace'),'stderr':q.stderr.decode(errors='replace')})
 except BaseException as e:r['queries'].append({'argv':a,'error_type':type(e).__name__})
print(json.dumps(r,sort_keys=True))
CHECK
