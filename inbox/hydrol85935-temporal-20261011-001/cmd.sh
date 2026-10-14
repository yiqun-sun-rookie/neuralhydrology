#!/bin/bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - <<'PYREMOTE'
from pathlib import Path
import json,hashlib,subprocess
r=Path('/data1/home/sunyiq/hydrol85935_temporal_attempts/hpc_v009_001/hydrol85935_temporal_persistence_20261011_001')
for n in ['control/queue_priority_20261014_001/status.json','control/queue_priority_20261014_001/watcher_registration.json','control/queue_priority_20261014_001/coordinator.log','control/submissions/main_s100.sbatch','control/submissions/main_s100.attempt.json','control/submissions/main_s100.json','logs/main_s100-242488_19.err','logs/main_s100-242488_19.out','control/parent_binding_v010.json','deployment_manifest.json','versions/v002/CONTROL.sha256']:
 p=r/n
 if p.exists():
  b=p.read_bytes();print('FILE '+json.dumps({'path':n,'sha256':hashlib.sha256(b).hexdigest(),'size':len(b),'text':b[-18000:].decode(errors='replace'),'tail_only':len(b)>18000}),flush=True)
for n in ['code/temporal_20261011/run.py','code/temporal_20261011/core.py','code/temporal_20261011/storage.py','code/temporal_hpc_v010.py','versions/v002/advance.py']:
 p=r/n;print('CODE '+json.dumps({'path':n,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}),flush=True)
for p in sorted((r/'control/submissions').glob('*.json')):print('SUBMISSION '+json.dumps({'path':str(p.relative_to(r)),'value':json.loads(p.read_text())}),flush=True)
q=subprocess.run(['squeue','-r','-h','-j','242488','-o','%i|%T|%M|%r|%C|%b|%N'],text=True,capture_output=True,timeout=45);print('QUEUE '+json.dumps({'rc':q.returncode,'stdout':q.stdout,'stderr':q.stderr}),flush=True)
PYREMOTE
