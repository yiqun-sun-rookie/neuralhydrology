#!/bin/bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY'
from pathlib import Path
import datetime,json,hashlib,subprocess
parent=Path('/data1/home/sunyiq/hydrol85935_revision_20261008_001')
root=Path('/data1/home/sunyiq/hydrol85935_temporal_persistence_20261011_001')
print(json.dumps(dict(observed_at=datetime.datetime.now().astimezone().isoformat(),scope='READ_ONLY_PARENT_LOCAL_SOURCE_REVIEW',advance_called=False,scientific_submissions=0)))
assert (root/'OWNER').read_text().strip()=='hydrol85935_temporal_persistence_20261011_001'
for rel in ['control/local_takeover_20261012_002/ownership.json','control/full_v004/jobs.json','control/continuation_v004/status.json']:
 p=parent/rel
 print(json.dumps(dict(parent_file=rel,content=p.read_text() if p.is_file() else None)))
jobs=json.loads((parent/'control/full_v004/jobs.json').read_text())
assert jobs==dict(train=240076,attacks=240077,report=240078)
for role,job in jobs.items():
 r=subprocess.run(['scontrol','show','job',str(job),'--oneliner'],text=True,capture_output=True,timeout=45)
 print(json.dumps(dict(role=role,job=job,returncode=r.returncode,stdout=r.stdout,stderr=r.stderr)))
for seed in (100,200,300):
 p=parent/f'execution/v004/training/s{seed}/complete.json'
 print(json.dumps(dict(old_remote_source='v004',seed=seed,complete_marker_exists=p.is_file())))
for rel in ['versions/v004/CODE.sha256','versions/v004/DATA.sha256']:
 p=parent/rel
 print(json.dumps(dict(parent_manifest=rel,sha256=hashlib.sha256(p.read_bytes()).hexdigest() if p.is_file() else None)))
for rel in ['control/submissions/preflight.json','control/submissions/main_s100.json','control/submissions/main_s200.json','control/submissions/main_s300.json','control/submissions/report.json']:
 p=root/rel
 print(json.dumps(dict(additional_submission_file=rel,content=p.read_text() if p.is_file() else None)))
print(json.dumps(dict(status='SOURCE_SWITCH_RECORDED_NO_OLD_CONTROLLER_ADVANCE',next_action='Wait for actual source models and verify a new source bridge; parent is read-only')))
PY
