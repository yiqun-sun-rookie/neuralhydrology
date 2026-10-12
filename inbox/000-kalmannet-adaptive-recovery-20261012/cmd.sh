#!/bin/bash
sequence=7
umask 077
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -I -S -B - <<'CHECK'
import os,json,base64,hashlib,datetime,subprocess
from pathlib import Path
B=Path('/data1/home/sunyiq/kalmannet_joint_adaptive_comparison_20261006_v1');C=B/'repair_coordination_cpu_successor_20261012_001'
r={'read_only':True,'scientific_submissions':0,'observed_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'files':{},'queries':[]}
assert os.getuid()==os.geteuid()==2272
for p in [C/'hold225_result.json']:
 if p.is_file() and not p.is_symlink() and p.stat().st_size<131072:
  b=p.read_bytes();r['files'][str(p)]={'bytes':len(b),'sha256':hashlib.sha256(b).hexdigest(),'base64':base64.b64encode(b).decode()}
 else:r['files'][str(p)]={'exists':p.exists()}
for p in [Path('/data1/home/sunyiq/kalmannet_cpu_remaining_fourteen_prefix_20261012_006'),Path('/data1/home/sunyiq/kalmannet_cpu_remaining_fourteen_prefix_20261012_006_transport_boot')]:r['files'][str(p)]={'exists':p.exists(),'symlink':p.is_symlink()}
for p in [Path('/data1/home/sunyiq/kalmannet_remaining_twelve_rtx3090_prefix_20261012_003'),Path('/data1/home/sunyiq/kalmannet_remaining_twelve_rtx3090_prefix_20261012_002')]:r['files'][str(p)]={'exists':p.exists(),'symlink':p.is_symlink()}
for a in [['squeue','--noheader','--user','sunyiq','--format=%i|%j|%T|%Z|%o'],['scontrol','show','job','241249','--oneliner'],['scontrol','show','partition','hcpu48y','--oneliner']]:
 try:
  q=subprocess.run(a,capture_output=True,stdin=subprocess.DEVNULL,timeout=20,env={**os.environ,'TZ':'UTC','LC_ALL':'C'});r['queries'].append({'argv':a,'returncode':q.returncode,'stdout':q.stdout.decode(errors='replace'),'stderr':q.stderr.decode(errors='replace')})
 except BaseException as e:r['queries'].append({'argv':a,'error_type':type(e).__name__})
print(json.dumps(r,sort_keys=True))
CHECK
