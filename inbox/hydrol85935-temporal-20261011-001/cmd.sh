#!/bin/bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY'
from pathlib import Path
import hashlib,json,tarfile,subprocess,datetime
root=Path('/data1/home/sunyiq/hydrol85935_temporal_persistence_20261011_001')
parent=Path('/data1/home/sunyiq/hydrol85935_revision_20261008_001')
target=root/'versions/v003'
payload=Path('/data1/home/sunyiq/hpc_mailbox/inbox/hydrol85935-temporal-20261011-001/payload/temporal_bridge_v003_hpc_v009_20261012_001.tar.gz')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
binding={'assignment_sha256': 'b044450cc6a5ab723c7b470423d0dedb0b581d7f6e00efd53f07fb9613068c6c', 'code_version': 'v004', 'execution_plan_version': 'hybrid_v009_20261012_001', 'execution_version': 'hpc_v009', 'historical_prediction_nse_tolerance': 0.0001, 'identity': 'hydrol85935_temporal_persistence_20261011_001', 'jobs': {'attacks': 241336, 'train': 241335, 'validate': 241337}, 'new_model_interface_nse_tolerance': 1e-05, 'parent_identity': 'hydrol85935_revision_20261008_001', 'parent_other_attacks_need_not_complete': True, 'parent_submission_receipt_sequence': 85, 'parent_submission_receipt_sha256': '68798a0e696c7705214c35181e04d4acf6252a3b3ea55a6afb9137062c6750f9', 'source_code_unchanged': True, 'source_control': 'control/hybrid_v009_20261012_001', 'source_files_manifest_sha256': '6ac9c97748e45270866c8640b567cbc85bfa5a14655ef852673d86e98290802f'}
assert root.resolve()==root and (root/'OWNER').read_text().strip()==root.name
assert not target.exists(), 'Keep existing v003 and reconcile its previous deployment receipt'
assert not (root/'frozen').exists(), 'Do not rebind after scientific output has frozen another source'
submissions=root/'control/submissions'
assert not submissions.exists() or not any(submissions.iterdir()), 'Preserve and reconcile any existing submission attempt'
checks={'versions/v004/CODE.sha256':'9b4b4fd7f3b49da4eda0b6e371d5a26bd68625800d5f084998e07569c22e68ac','control/full_v004/FULL.sha256':'d5dfc837d6b4dcec417419653bbdb834518f82860ffdcdb1de3619e64db42db6','control/continuation_v004/reproduction_acceptance_amendment.json':'2325729582c264dae40b226b8c1189196077e7cf2a768f6c715080375d0825ed'}
for relative,expected in checks.items():assert sha(parent/relative)==expected,relative
source=parent/binding['source_control']
assert sha(source/'FILES.sha256')==binding['source_files_manifest_sha256']
for line in (source/'FILES.sha256').read_text().splitlines():
 expected,relative=line.split(None,1)
 path=(source/relative).resolve(strict=True)
 assert path.is_relative_to(source.resolve()) and sha(path)==expected,relative
assert sha(source/'assignment.json')==binding['assignment_sha256']
assert json.loads((source/'assignment.json').read_text())['hpc_training_seeds']==[100,200,300]
assert json.loads((source/'jobs.json').read_text())==binding['jobs']
assert sha(root/'versions/v002/controller_manifest.json')=='5179fe2484809c091a8f97a63de3281d7d6a20b502bc343a032a6311619f4fe6'
for relative,expected in json.loads((root/'deployment_manifest.json').read_text())['sha256'].items():assert sha(root/relative)==expected
assert sha(payload)=='88ecc3dedffc60cd4c5117623fbcdb9391361e615510631fd7e7e1c1dc5fc04b'
with tarfile.open(payload) as archive:
 assert set(archive.getnames())=={'advance.py','authorization.json','parent_source_binding.json','controller_manifest.json'}
 values={}
 for member in archive.getmembers():
  assert member.isfile() and Path(member.name).name==member.name
  values[member.name]=archive.extractfile(member).read()
 manifest=json.loads(values['controller_manifest.json'])
 assert hashlib.sha256(values['controller_manifest.json']).hexdigest()=='b547c53644b06f0771c00e79160fadf8ec5f3f9ba43d779aa3c292963c49dc2c'
 for name,expected in manifest['sha256'].items():assert hashlib.sha256(values[name]).hexdigest()==expected
 compile(values['advance.py'],str(target/'advance.py'),'exec')
 target.mkdir(parents=True)
 for name,data in values.items():
  with (target/name).open('xb') as stream:stream.write(data)
print(json.dumps(dict(status='ADDITIONAL_CONTROLLER_V003_DEPLOYED_BOUND_TO_HPC_V009',parent_written=False,scientific_code_changed=False,controller_manifest_sha256=sha(target/'controller_manifest.json'),source_binding=binding,observed_at=datetime.datetime.now().astimezone().isoformat())))
queue=subprocess.run(['squeue','--noheader','-j',','.join(str(j) for j in binding['jobs'].values()),'--format=%i|%T|%r|%M'],capture_output=True,text=True,timeout=45,check=True)
print(json.dumps(dict(parent_actual_jobs=queue.stdout.splitlines())))
for seed in (100,200,300):
 execution=parent/'execution/hpc_v009';folder=execution/f'training/s{seed}'
 checkpoints=sorted(folder.glob('runs/*/model_epoch*.pt'))
 print(json.dumps(dict(parent_execution=str(execution),training_seed=seed,completion_marker_exists=(folder/'complete.json').is_file(),checkpoint_count=len(checkpoints),latest_checkpoint=checkpoints[-1].name if checkpoints else None)))
PY
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B /data1/home/sunyiq/hydrol85935_temporal_persistence_20261011_001/versions/v003/advance.py --root /data1/home/sunyiq/hydrol85935_temporal_persistence_20261011_001 --parent /data1/home/sunyiq/hydrol85935_revision_20261008_001 --version v004
