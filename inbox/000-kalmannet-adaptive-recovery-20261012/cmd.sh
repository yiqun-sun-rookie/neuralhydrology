#!/bin/bash
sequence=9
umask 077
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -I -S -B - <<'CHECK'
import os,json,base64,hashlib,datetime
from pathlib import Path
R=Path('/data1/home/sunyiq/kalmannet_cpu_remaining_fourteen_prefix_20261012_006')
assert os.getuid()==os.geteuid()==2272
r={'read_only':True,'scientific_submissions':0,'observed_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'files':{}}
for p in sorted((R/'output/case_025').rglob('*'))+sorted((R/'output/runtime').glob('case_025*')):
 if p.is_file() and not p.is_symlink():
  b=p.read_bytes()
  r['files'][str(p)]={'bytes':len(b),'sha256':hashlib.sha256(b).hexdigest()}
  if len(b)<=1024**2:r['files'][str(p)]['base64']=base64.b64encode(b).decode()
print(json.dumps(r,sort_keys=True))
CHECK
