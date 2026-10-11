#!/bin/bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY'
from pathlib import Path
import json,re
parent=Path('/data1/home/sunyiq/hydrol85935_revision_20261008_001')
versions={name:sorted(p.name for p in (parent/name).iterdir() if p.is_dir() and re.fullmatch(r'v[0-9]{3}',p.name)) for name in ('versions','execution')}
print(json.dumps({'parent_version_check':versions}))
if any(items and items[-1]!='v003' for items in versions.values()):
    raise SystemExit('PARENT_VERSION_CHANGE_REQUIRES_INTERFACE_REVIEW')
PY
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B /data1/home/sunyiq/hydrol85935_temporal_persistence_20261011_001/code/advance.py --root /data1/home/sunyiq/hydrol85935_temporal_persistence_20261011_001 --parent /data1/home/sunyiq/hydrol85935_revision_20261008_001 --version v003
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY'
from pathlib import Path
import json,datetime,subprocess
parent=Path('/data1/home/sunyiq/hydrol85935_revision_20261008_001')
print(json.dumps({'read_only_parent_diagnostic_observed':datetime.datetime.now().astimezone().isoformat()}))
for name in ['control/continuation_v003/status.json','diagnostics/matched_runtime_20261009/summary.json','diagnostics/path_trace_20261009_001/summary.json','control/full_v003/jobs.json']:
    p=parent/name
    print(json.dumps({'parent_file':name,'exists':p.is_file(),'content':json.loads(p.read_text()) if p.is_file() else None}))
for seed in [100,200,300]:
    folder=parent/'execution/v003/training'/('s'+str(seed))
    marker=folder/'complete.json'
    print(json.dumps({'training_seed':seed,'training_directory_exists':folder.is_dir(),'completion_marker_exists':marker.is_file(),'registered_training_content':json.loads(marker.read_text()) if marker.is_file() else None,'direct_entries':sorted(p.name for p in folder.iterdir()) if folder.is_dir() else []}))
result=subprocess.run(['sacct','-j','237696,237883,237904,237936,238679,238886','-X','-n','-P','--format=JobID,State,ExitCode,Elapsed,End'],text=True,capture_output=True,timeout=60,check=True)
print(json.dumps({'registered_parent_jobs':result.stdout.splitlines()}))
PY
