#!/bin/bash
sequence=10
umask 077
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -I -S -B - <<'CHECK'
import os,json,datetime,subprocess
from pathlib import Path
assert os.getuid()==os.geteuid()==2272
roots=['/data1/home/sunyiq/kalmannet_cpu_remaining_fourteen_prefix_20261012_007','/data1/home/sunyiq/kalmannet_cpu_remaining_fourteen_prefix_20261012_007_transport_boot','/data1/home/sunyiq/kalmannet_remaining_twelve_rtx3090_prefix_20261012_004','/data1/home/sunyiq/kalmannet_remaining_twelve_rtx3090_prefix_20261012_004_transport_boot']
r={'read_only':True,'scientific_submissions':0,'observed_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'roots':{p:{'exists':Path(p).exists(),'symlink':Path(p).is_symlink()} for p in roots},'queries':[]}
for a in [['squeue','--noheader','--user','sunyiq','--format=%i|%j|%T|%Z|%o'],['scontrol','show','job','241249','--oneliner']]:
 try:
  q=subprocess.run(a,capture_output=True,stdin=subprocess.DEVNULL,timeout=20,env={**os.environ,'TZ':'UTC','LC_ALL':'C'})
  r['queries'].append({'argv':a,'returncode':q.returncode,'stdout':q.stdout.decode(errors='replace'),'stderr':q.stderr.decode(errors='replace')})
 except BaseException as e:r['queries'].append({'argv':a,'error_type':type(e).__name__})
print(json.dumps(r,sort_keys=True))
CHECK
