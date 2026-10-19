#!/bin/bash
set -eo pipefail
export TZ=UTC
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -u -B - <<'PY'
import subprocess,json,datetime,re
from pathlib import Path
def call(args):
 try:
  p=subprocess.run(args,capture_output=True,text=True,timeout=20);return dict(returncode=p.returncode,stdout=p.stdout,stderr=p.stderr)
 except subprocess.TimeoutExpired:return dict(returncode=124,stdout='',stderr='read-only command timeout')
helpformat=call(['sacct','--helpformat']);available=set(re.findall(r'\b[A-Za-z][A-Za-z0-9_]*\b',helpformat['stdout']))
requested=['JobID','JobName','User','State','ExitCode','ElapsedRaw','AllocCPUS','ReqMem','Submit','Start','End','NodeList','NNodes','WorkDir','Comment','SystemComment']
fields=[x for x in requested if x in available]
assert set(['JobID','JobName','State','ExitCode','ElapsedRaw'])<=set(fields)
fmt=','.join(x+('%180' if x=='WorkDir' else '%120' if x in ['Comment','SystemComment'] else '') for x in fields)
accounting=call(['sacct','-j','245347','--noheader','--parsable2','--format='+fmt])
queue=call(['squeue','-u','sunyiq','-n','knet_init_probe','-h','-o','%i|%j|%T|%M|%R'])
print('NATIVE_IDENTITY_DIAGNOSTIC='+json.dumps(dict(utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),fields=fields,helpformat=helpformat,accounting=accounting,queue=queue,run_directory_exists=Path('/data1/home/sunyiq/knet_camels_hpc_20261012_001/attempts/state_channel_repair_probe_20261019_001/runs/04105700/attempt_001').exists(),exact_script_binding_available=any(x in available for x in ['SubmitLine','Command']))),flush=True)
PY
