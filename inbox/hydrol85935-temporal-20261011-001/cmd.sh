#!/bin/bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY'
from pathlib import Path
import hashlib,json,tarfile,subprocess
root=Path('/data1/home/sunyiq/hydrol85935_temporal_persistence_20261011_001')
parent=Path('/data1/home/sunyiq/hydrol85935_revision_20261008_001')
target=root/'versions/v002'
payload=Path('/data1/home/sunyiq/hpc_mailbox/inbox/hydrol85935-temporal-20261011-001/payload/temporal_bridge_v002_28994ee5a248.tar.gz')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert root.resolve()==root and (root/'OWNER').read_text().strip()==root.name
assert sha(payload)=='28994ee5a248c87d4889f6d1312804ae766d6afead072cad3e6a81fb1de64d4a'
assert not target.exists() and not (root/'control/submissions').exists() and not (root/'frozen').exists()
binding={'version': 'v004', 'code_manifest_sha256': '9b4b4fd7f3b49da4eda0b6e371d5a26bd68625800d5f084998e07569c22e68ac', 'full_manifest_sha256': 'd5dfc837d6b4dcec417419653bbdb834518f82860ffdcdb1de3619e64db42db6', 'acceptance_amendment_sha256': '2325729582c264dae40b226b8c1189196077e7cf2a768f6c715080375d0825ed', 'baseline_nse_tolerance': 0.0001, 'new_model_interface_tolerance': 1e-05}
checks={'versions/v004/CODE.sha256':binding['code_manifest_sha256'],'control/full_v004/FULL.sha256':binding['full_manifest_sha256'],'control/continuation_v004/reproduction_acceptance_amendment.json':binding['acceptance_amendment_sha256']}
for rel,expected in checks.items():assert sha(parent/rel)==expected,rel
for rel,expected in json.loads((root/'deployment_manifest.json').read_text())['sha256'].items():assert sha(root/rel)==expected
target.mkdir(parents=True)
with tarfile.open(payload) as tar:
    assert set(tar.getnames())=={'advance.py','authorization.json','controller_manifest.json'}
    for m in tar.getmembers():
        assert m.isfile() and Path(m.name).name==m.name
        with (target/m.name).open('xb') as f:f.write(tar.extractfile(m).read())
for rel,expected in json.loads((target/'controller_manifest.json').read_text())['sha256'].items():assert sha(target/rel)==expected
print(json.dumps({'status':'ADDITIONAL_CONTROLLER_V002_DEPLOYED_BOUND_TO_EXISTING_PARENT_V004','parent_written':False,'parent_binding':binding,'controller_manifest_sha256':sha(target/'controller_manifest.json')}))
jobs=set()
for rel in ['control/continuation_v004/status.json','control/preflight_v004_job_id','control/resource_pilot_v004_job_id','control/full_v004/jobs.json']:
    p=parent/rel
    if p.exists():
        value=p.read_text()
        print(json.dumps({'parent_file':rel,'content':value}))
        if rel.endswith('_job_id'):jobs.add(value.strip())
        if rel.endswith('jobs.json'):jobs.update(str(v) for v in json.loads(value).values())
if jobs:
    result=subprocess.run(['sacct','-j',','.join(sorted(jobs)),'-n','-P','--format=JobID,State,ExitCode,Elapsed'],capture_output=True,text=True,timeout=60,check=True)
    print(json.dumps({'parent_registered_jobs':result.stdout.splitlines()}))

PY
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B /data1/home/sunyiq/hydrol85935_temporal_persistence_20261011_001/versions/v002/advance.py --root /data1/home/sunyiq/hydrol85935_temporal_persistence_20261011_001 --parent /data1/home/sunyiq/hydrol85935_revision_20261008_001 --version v004
