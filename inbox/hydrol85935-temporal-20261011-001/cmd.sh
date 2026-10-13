#!/bin/bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - <<'PY'
import ast,hashlib,json
from pathlib import Path
p=Path('/data1/home/sunyiq/hydrol85935_revision_20261008_001')
v=p/'control/hybrid_v012_20261013_001'
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def read(path):return json.loads(path.read_text(encoding='utf8'))
expected={'assignment.json': '71e22779e3088b45e91df4bbd09c3becf592eaece9bd44d158ce306ef72c31c6', 'previous_assignment.json': '40bf00394e99d3785a47add4f83b937658a47ca66d41b32a8051fe7ec1f6ab0e', 'worker.py': 'b09f6d157f8ae90b4e285fe9469a89dc69258255082b53c26d799c2677309c0e', 'worker_bridge.py': '5fa931f34e573e1ef49bdd18ab7171fab20582560a3c196aef241c50e5405fb5', 'export_bridge.py': '9ec6ee894e9714470591cfa43521d3bcb3f77fbb7794e4b886c98c4859af392b', 'federated_v010.py': 'a2f0234fb9e5003522105b92975a72b9b0f4db6bbbbf5125391487213dcf2aee'}
for name,digest in expected.items():assert sha(v/name)==digest,name
assert sha(p/'control/hybrid_v009_20261012_001/worker.py')==expected['worker_bridge.py']
assert sha(p/'control/workflow_v010_20261012_001/federated_v010.py')==expected['export_bridge.py']
original=p/'control/hybrid_v011_20261013_001/original_worker_v009.py'
assert sha(original)=='c5740af702e1302fa93cf2211bb7dd8b034cf49d60b0fb28d8f0b138d134d924'
old_assignment=p/'control/hybrid_v009_20261012_001/assignment.json'
assert sha(old_assignment)=='b044450cc6a5ab723c7b470423d0dedb0b581d7f6e00efd53f07fb9613068c6c'
a=read(old_assignment);b=read(v/'assignment.json')
assert a['hpc_training_seeds']==b['hpc_training_seeds']==[100,200,300]
for key in ['scientific_code','output','science_rules_changed']:assert a[key]==b[key],key
for key in ['hpc_gpus','hpc_cpu_cores']:assert a['resource_limits'][key]==b['resource_limits'][key],key
assert b['resource_limits']['hpc_gpus']==1 and b['resource_limits']['hpc_cpu_cores']==4
assert b['scientific_code']==str(p/'versions/v004/code') and b['output']==str(p/'execution/hpc_v009')
assert [t for t in a['hpc_tasks'] if t['model']!='original_s100']==[t for t in b['hpc_tasks'] if t['model']!='original_s100']
def train_branch(path):
 for node in ast.walk(ast.parse(path.read_text(encoding='utf8'))):
  if isinstance(node,ast.If) and ast.unparse(node.test)=="args.stage == 'train'":return ast.dump(ast.Module(body=node.body,type_ignores=[]),include_attributes=False)
 raise ValueError('training branch missing')
assert train_branch(v/'worker.py')==train_branch(original)
print('PARENT_DISTRIBUTION_REVIEW '+json.dumps({'orchestration_version':'hybrid_v012_20261013_001','assignment_sha256':expected['assignment.json'],'historical_binding_assignment_sha256':sha(old_assignment),'parent_model_execution':str(p/'execution/hpc_v009'),'parent_science_code':str(p/'versions/v004/code'),'training_branch_unchanged':True,'hpc_training_job':241335,'actual_model_assets_verified':False,'only_original_model_attack_scope_reallocated':True,'additional_gpu_limit':1,'additional_cpu_limit':4}),flush=True)
PY
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - <<'PY'
import hashlib, json, re, subprocess, sys
from pathlib import Path

parent = Path('/data1/home/sunyiq/hydrol85935_revision_20261008_001')
root = Path('/data1/home/sunyiq/hydrol85935_temporal_attempts/hpc_v009_001/hydrol85935_temporal_persistence_20261011_001')
def sha(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''): h.update(block)
    return h.hexdigest()
def read(path): return json.loads(path.read_text(encoding='utf8'))
assert root.resolve() == root and parent.resolve() == parent
assert not root.is_relative_to(parent) and not parent.is_relative_to(root)
assert (root / 'OWNER').read_text().strip() == root.name
assert (parent / 'OWNER').read_text().strip() == parent.name
assert sha(root / 'deployment_manifest.json') == '821e431a231448d656f3c40e5b1809fb8d2746b9dbbcd29b250267d9ff87964e'
inventory = read(root / 'deployment_manifest.json')
for relative, expected in inventory['sha256'].items():
    path = (root / relative).resolve(strict=True)
    assert path.is_relative_to(root) and sha(path) == expected, relative
assert sha(root / 'versions/v002/controller_manifest.json') == '94041e68d4a8242f1dbb70d26db37b2562dbe915c5e36a8741af97d6ec63406f'
binding = read(root / 'control/parent_binding_v010.json')
assert binding['parent_code_version'] == 'v004' and binding['parent_execution_version'] == 'hpc_v009'
assert binding['parent_execution'] == str(parent / 'execution/hpc_v009')
assert binding['serial_dependency_job'] == 241344 and binding['parent_training_job'] == 241335
assert binding['parent_validation_job'] == 241337 and binding['new_model_interface_tolerance'] == 0.00001
assignment = parent / 'control/hybrid_v009_20261012_001/assignment.json'
assert sha(assignment) == binding['assignment_sha256'] == 'b044450cc6a5ab723c7b470423d0dedb0b581d7f6e00efd53f07fb9613068c6c'
assert read(parent / 'control/hybrid_v009_20261012_001/jobs.json') == {'train':241335, 'attacks':241336, 'validate':241337}
assert read(parent / 'control/workflow_v010_20261012_001/jobs.json') == {'export':241344}
preflight = read(root / 'control/submissions/preflight.json')
assert preflight['job_id'] == 241345 and preflight['serial_parent_dependency'] == 241344
assert preflight['deployment_sha256'] == '94041e68d4a8242f1dbb70d26db37b2562dbe915c5e36a8741af97d6ec63406f'
assert preflight['actual_parent_execution'] == 'hpc_v009' and preflight['parent_version'] == 'v004'
assert sha(root / 'control/submissions/preflight.sbatch') == preflight['script_sha256'] == '093faa4894aab80834c8e475e02b0b7a86cab8bc45a9a835baa58f478f00f57e'
print('SOURCE_V010 ' + json.dumps({'root':str(root), 'binding':binding, 'preflight':preflight, 'old_controller_executed':False}), flush=True)
jobs = [(241335, parent/'control/hybrid_v009_20261012_001/train.sbatch', parent/'control/hybrid_v009_20261012_001'),
        (241336, parent/'control/hybrid_v009_20261012_001/attacks.sbatch', parent/'control/hybrid_v009_20261012_001'),
        (241337, parent/'control/hybrid_v009_20261012_001/validate.sbatch', parent/'control/hybrid_v009_20261012_001'),
        (241344, parent/'control/workflow_v010_20261012_001/export.sbatch', Path('/data1/home/sunyiq/hpc_mailbox')),
        (241345, root/'control/submissions/preflight.sbatch', Path('/data1/home/sunyiq/hpc_mailbox'))]
for jid, command, workdir in jobs:
    result = subprocess.run(['scontrol','show','job','-o',str(jid)], capture_output=True, text=True, timeout=30)
    print('REGISTERED_JOB ' + json.dumps({'job_id':jid, 'returncode':result.returncode, 'stdout':result.stdout, 'stderr':result.stderr}), flush=True)
    if result.returncode == 0:
        assert 'Command='+str(command)+' ' in result.stdout and 'WorkDir='+str(workdir)+' ' in result.stdout
        assert 'NumCPUs=4 ' in result.stdout and re.search(r'TresPerNode=(?:gres:)?gpu:1(?:\s|$)', result.stdout)
    else:
        account = subprocess.run(['sacct','-j',str(jid),'-n','-P','--format=JobID,State,ExitCode'], capture_output=True, text=True, timeout=30, check=True)
        print('ARCHIVED_JOB ' + json.dumps({'job_id':jid, 'stdout':account.stdout}), flush=True)
        assert account.stdout.strip(), 'Unknown registered job outcome; reconcile before advancing'
models = []
for seed in (100,200,300):
    folder = parent / 'execution/hpc_v009/training' / ('s'+str(seed))
    models.append({'seed':seed, 'complete_marker_exists':(folder/'complete.json').is_file(),
                   'epoch30_weights': [str(p.relative_to(parent/'execution/hpc_v009')) for p in folder.rglob('model_epoch030.pt')]})
print('MODEL_PROGRESS ' + json.dumps(models), flush=True)
submissions = [read(p) for p in sorted((root/'control/submissions').glob('*.json')) if not p.name.endswith('.attempt.json')]
print('EXISTING_SUBMISSIONS ' + json.dumps(submissions), flush=True)
# The preflight is already registered. Never pass --register-after here.
subprocess.run([sys.executable, str(root/'code/temporal_hpc_v010.py'), '--root',str(root), '--parent',str(parent)], check=True, timeout=360)
PY
