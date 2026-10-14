#!/bin/bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - <<'PY'
import subprocess,json,time
commands=[('JOB',['scontrol','show','job','241345']),('START',['squeue','--start','-j','241345']),('NODES',['sinfo','-N','-h','-p','hgpu2p','-O','NodeList:22,StateLong:16,Gres:38,GresUsed:55,CPUsState:25']),('PARTITIONS',['sinfo','-h','-o','%P|%a|%l|%D|%t|%G']),('OWN_ACTIVE',['squeue','-h','-u','sunyiq','-t','RUNNING,COMPLETING','-o','%i|%P|%j|%N|%b|%C']),('PARTITION',['scontrol','show','partition','hgpu2p'])]
print('TIME '+str(time.time()),flush=True)
for name,cmd in commands:
 r=subprocess.run(cmd,capture_output=True,text=True,timeout=60)
 print(name+' '+json.dumps({'rc':r.returncode,'stdout':r.stdout,'stderr':r.stderr}),flush=True)
PY
