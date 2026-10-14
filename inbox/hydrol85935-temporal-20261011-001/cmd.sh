#!/bin/bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - <<'PY'
from pathlib import Path
import json,subprocess,time
p=Path('/data1/home/sunyiq/hydrol85935_revision_20261008_001')
o=p/'execution/hpc_v009'
r=Path('/data1/home/sunyiq/hydrol85935_temporal_attempts/hpc_v009_001/hydrol85935_temporal_persistence_20261011_001')
t=json.loads((p/'control/hybrid_v013_20261014_001/assignment.json').read_text())['hpc_tasks'][6]
rows=[]
for b in t['basins']:
 times=[(o/'records/attacks'/c/b/'complete.json').stat().st_mtime for c in t['combinations'] if (o/'records/attacks'/c/b/'complete.json').is_file()]
 rows.append({'basin':b,'completed':len(times),'first':min(times) if times else None,'last':max(times) if times else None})
q=subprocess.run(['squeue','-r','-h','-j','241336,241345','-o','%i|%T|%M|%r'],capture_output=True,text=True,check=True,timeout=45).stdout.splitlines()
print('ETA_REFRESH '+json.dumps({'unix':time.time(),'rows':rows,'current_jobs':[x for x in q if x.startswith(('241336_6|','241345|'))],'held_parent_tasks':sum('JobHeld' in x for x in q),'coordinator_status':json.loads((r/'control/queue_priority_20261014_001/status.json').read_text())}),flush=True)
for name in ['control/new_models_verified.json','control/resource_pilot.json']:
 f=r/name
 if f.exists():print('RESULT '+json.dumps({'path':name,'value':json.loads(f.read_text())}),flush=True)
PY
