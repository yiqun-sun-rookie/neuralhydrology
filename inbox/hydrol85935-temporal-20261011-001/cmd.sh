#!/bin/bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
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
        assert 'NumCPUs=4 ' in result.stdout and 'TresPerNode=gres:gpu:1' in result.stdout
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
