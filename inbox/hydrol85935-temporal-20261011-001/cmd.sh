#!/bin/bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY'
import datetime,json,subprocess
from pathlib import Path
def inspect(label,args):
    result=subprocess.run(args,text=True,capture_output=True,timeout=45)
    print(json.dumps({'inspection':label,'exit_code':result.returncode,'stdout':result.stdout,'stderr':result.stderr}))
    if result.returncode:
        raise SystemExit(result.returncode)
print(json.dumps({'observed_at':datetime.datetime.now().astimezone().isoformat(),'scope':'read-only alternative node and queued-job inspection; no submissions or changes'}))
inspect('partition_node_states',['sinfo','-p','hgpu2p,hgpu2,hgpu4,hgpu8','-o','%.12P %.6a %.6D %.12t %.60N'])
for partition in ['hgpu2p','hgpu2','hgpu4','hgpu8']:
    inspect(partition+'_resources',['sinfo','-p',partition,'-N','-O','nodelist:18,gres:20,gresused:40,cpusstate:20'])
    inspect(partition+'_policy',['scontrol','show','partition',partition,'-o'])
inspect('registered_training_job',['scontrol','show','job','240076','-o'])
inspect('registered_training_estimated_start',['squeue','-j','240076','-h','--start','-o','%i|%P|%T|%S|%r'])
inspect('candidate_node_metadata',['scontrol','show','node','ngu[001-002,004-008,010-011,003,009,101-104,201-203]','-o'])
parent=Path('/data1/home/sunyiq/hydrol85935_revision_20261008_001')
for name in ['control/full_v004/jobs.json','control/continuation_v004/status.json']:
    p=parent/name
    print(json.dumps({'parent_file':name,'content':json.loads(p.read_text()) if p.is_file() else None}))
PY
