#!/bin/bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - <<'PY'
import json,hashlib,subprocess
from pathlib import Path
c=Path('/data1/home/sunyiq/hydrol85935_temporal_attempts/hpc_v009_001/hydrol85935_temporal_persistence_20261011_001/control/queue_priority_20261014_001')
expected='a3de8ee97281cb5b1ff7ab745bd8b4506abf3da932d35869b08eec3d0631fe6e'
assert hashlib.sha256((c/'queue_priority.py').read_bytes()).hexdigest()==expected
applied=json.loads((c/'applied.json').read_text());registration=json.loads((c/'watcher_registration.json').read_text());pid=registration['pid'];proc=Path('/proc')/str(pid)
alive=False
if proc.exists():
 ticks=proc.joinpath('stat').read_text().split()[21]
 cmd=proc.joinpath('cmdline').read_bytes().split(b'\0')
 alive=ticks==registration['proc_start_ticks'] and str(c/'queue_priority.py').encode() in cmd and b'watch' in cmd
print('PRIORITY_COORDINATOR '+json.dumps({'alive':alive,'registration':registration,'applied':applied,'status':json.loads((c/'status.json').read_text())}),flush=True)
r=subprocess.run(['squeue','-r','-h','-u','sunyiq','-o','%i|%T|%r'],text=True,capture_output=True,timeout=45,check=True)
rows=[x for x in r.stdout.splitlines() if x.split('|')[0].split('_')[0] in ['241336','241337','241344','241345']]
print('PRIORITY_QUEUE '+json.dumps(rows),flush=True)
root=c.parent.parent
for name in ['control/new_models_verified.json','control/resource_pilot.json','reports/coverage_and_summary.json']:
 p=root/name
 if p.is_file():print('PRIORITY_RESULT '+json.dumps({'path':name,'value':json.loads(p.read_text())}),flush=True)
print('PRIORITY_SUBMISSIONS '+json.dumps([json.loads(p.read_text()) for p in sorted((root/'control/submissions').glob('*.json')) if not p.name.endswith('.attempt.json')]),flush=True)
PY
