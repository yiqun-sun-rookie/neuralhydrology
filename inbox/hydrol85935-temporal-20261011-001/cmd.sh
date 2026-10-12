#!/bin/bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY'
from pathlib import Path
import datetime,json,re,subprocess
parent=Path('/data1/home/sunyiq/hydrol85935_revision_20261008_001')
print(json.dumps({'observed_at':datetime.datetime.now().astimezone().isoformat()}))
versions={name:sorted(v.name for v in (parent/name).iterdir() if v.is_dir() and re.fullmatch(r'v[0-9]{3}',v.name)) for name in ('versions','execution')}
print(json.dumps({'parent_versions':versions}))
if any(names and names[-1]!='v004' for names in versions.values()):
    raise SystemExit('PARENT_VERSION_CHANGE_REQUIRES_REVIEW')
jobs=set()
for rel in ['control/continuation_v004/status.json','control/preflight_v004_job_id','control/resource_pilot_v004_job_id','control/full_v004/jobs.json']:
    path=parent/rel
    value=path.read_text() if path.is_file() else None
    print(json.dumps({'parent_file':rel,'content':value}))
    if value is not None:
        if rel.endswith('_job_id'):jobs.add(value.strip())
        if rel.endswith('jobs.json'):jobs.update(str(v) for v in json.loads(value).values())
assert all(re.fullmatch(r'[0-9]+',v) for v in jobs), jobs
if jobs:
    r=subprocess.run(['sacct','-j',','.join(sorted(jobs)),'-n','-P','--format=JobID,State,ExitCode,Elapsed,Start'],text=True,capture_output=True,timeout=45,check=True)
    print(json.dumps({'parent_registered_jobs':r.stdout.splitlines()}))
queue=subprocess.run(['squeue','--noheader','--user','sunyiq','--format=%i|%T|%r|%M|%l'],text=True,capture_output=True,timeout=45,check=True)
owned=[line.strip() for line in queue.stdout.splitlines() if line.split('|',1)[0].strip().split('_',1)[0] in jobs]
print(json.dumps({'parent_queue_status':owned}))
for seed in [100,200,300]:
    folder=parent/'execution/v004/training'/('s'+str(seed))
    marker=folder/'complete.json'
    print(json.dumps({'training_seed':seed,'training_directory_exists':folder.is_dir(),'completion_marker_exists':marker.is_file(),'completion':json.loads(marker.read_text()) if marker.is_file() else None}))
    checkpoints=sorted(folder.glob('runs/*/model_epoch*.pt'))
    epochs=[int(re.search(r'model_epoch([0-9]+)',p.name).group(1)) for p in checkpoints if re.search(r'model_epoch([0-9]+)',p.name)]
    print(json.dumps({'training_checkpoint_progress':{'seed':seed,'saved_checkpoint_count':len(checkpoints),'latest_saved_epoch':max(epochs) if epochs else None}}))
PY
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B /data1/home/sunyiq/hydrol85935_temporal_persistence_20261011_001/versions/v002/advance.py --root /data1/home/sunyiq/hydrol85935_temporal_persistence_20261011_001 --parent /data1/home/sunyiq/hydrol85935_revision_20261008_001 --version v004
