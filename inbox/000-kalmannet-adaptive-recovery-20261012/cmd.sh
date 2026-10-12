#!/bin/bash
sequence=4
umask 077
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -I -B - <<'CHECK'
import os,json,base64,hashlib,datetime,subprocess
from pathlib import Path
B=Path('/data1/home/sunyiq/kalmannet_joint_adaptive_comparison_20261006_v1');C=B/'repair_coordination_probe005_20261012_001'
r={'read_only':True,'scientific_submissions':0,'observed_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'files':{},'queries':[]}
assert os.getuid()==os.geteuid()==2272
for p in [C/'release224_result.json',C/'release_intent_224.json']+[B/'transport/sequence_224'/n for n in ('controller.log','stdout','stderr','result.json')]:
 if p.is_file() and not p.is_symlink() and p.stat().st_size<131072:
  b=p.read_bytes();r['files'][str(p)]={'bytes':len(b),'sha256':hashlib.sha256(b).hexdigest(),'base64':base64.b64encode(b).decode()}
 else:r['files'][str(p)]={'exists':p.exists()}
for a in [['scontrol','show','job','241249'],['scontrol','show','nodes','--details','ngu201,ngu202,ngu203']]:
 try:
  q=subprocess.run(a,capture_output=True,stdin=subprocess.DEVNULL,timeout=20);r['queries'].append({'argv':a,'returncode':q.returncode,'stdout':q.stdout.decode(errors='replace')[:131072],'stderr':q.stderr.decode(errors='replace')[:16384]})
 except BaseException as e:r['queries'].append({'argv':a,'error_type':type(e).__name__})
print(json.dumps(r,sort_keys=True))
CHECK
