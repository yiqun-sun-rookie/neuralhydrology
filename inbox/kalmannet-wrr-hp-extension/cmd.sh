#!/usr/bin/env bash
# Read-only diagnosis of failed environment activation. Never activate or submit.
set -euo pipefail
python3 -I -B - <<'PY'
import datetime
import hashlib
import json
import os
import pathlib
import subprocess

family = pathlib.Path('/data1/home/sunyiq/kalmannet_wrr_model_selection_20260908')
target = family / 'stages/B'
payload = pathlib.Path('/data1/home/sunyiq/hpc_mailbox/payload/kalmannet-wrr-hp-extension/model-selection20260908-stage-B-v1')
assert family.is_dir() and not family.is_symlink()
assert payload.is_dir() and payload.resolve() == payload
raw = (payload / 'TRANSPORT_MANIFEST.json').read_bytes()
assert hashlib.sha256(raw).hexdigest() == '2b437ca7d6a5337eb3d0eee401200cdc596bfa84571157129b27b11165525bea'
manifest = json.loads(raw)
allowed = set(manifest['files']) | {'TRANSPORT_MANIFEST.json', 'launch.sh'}
entries = list(payload.rglob('*'))
assert all(not path.is_symlink() for path in entries)
assert {path.relative_to(payload).as_posix() for path in entries if path.is_file()} == allowed
hashes = {}
for name, expected in manifest['files'].items():
    path = payload / name
    assert path.is_file()
    actual = hashlib.sha256(path.read_bytes()).hexdigest()
    assert actual == expected, name
    hashes[name] = actual
assert hashlib.sha256((payload / 'launch.sh').read_bytes()).hexdigest() == 'b2ee899990b42a06436fb3afa5d415be0feaaa7cd141212a137b60ffb1361d7f'
controls = {}
for name in ('DEPLOYMENT_RECEIPT.json', 'SUBMISSION_INTENT.json', 'SUBMISSION_RESPONSE.json', 'SUBMISSION_RECEIPT.json', 'array_job_id.txt'):
    path = target / name
    item = {'exists': os.path.lexists(path)}
    if item['exists']:
        assert path.is_file() and not path.is_symlink() and target.resolve() == target
        data = path.read_bytes()
        item.update(bytes=len(data), sha256=hashlib.sha256(data).hexdigest(), content=data.decode('utf-8'))
    controls[name] = item
hook = pathlib.Path('/data1/home/sunyiq/miniconda3/envs/knet_clean/etc/conda/activate.d/libblas_mkl_activate.sh')
assert hook.is_file()
hook_bytes = hook.read_bytes()
assert len(hook_bytes) < 65536
command = ['squeue', '-r', '-h', '-u', 'sunyiq', '-o', '%i|%T|%Z']
response = subprocess.run(command, capture_output=True, text=True, check=False, timeout=45)
active = []
if response.returncode == 0:
    for line in response.stdout.splitlines():
        parts = line.split('|')
        assert len(parts) == 3
        if parts[2] == str(family) or parts[2].startswith(str(family) + '/'):
            active.append({'job_id': parts[0], 'state': parts[1], 'workdir': parts[2]})
report = {
    'kind': 'READ_ONLY_STAGE_B_ACTIVATION_DIAGNOSIS_NOT_RETRY',
    'observed_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'stage_B_root': str(target), 'stage_B_exists': os.path.lexists(target),
    'stage_B_controls': controls, 'active_family_jobs': active,
    'scheduler_query': {'command': command, 'returncode': response.returncode, 'stdout': response.stdout, 'stderr': response.stderr},
    'transport_verified_files': hashes,
    'activation_hook': {'path': str(hook), 'sha256': hashlib.sha256(hook_bytes).hexdigest(), 'content': hook_bytes.decode('utf-8')},
    'MKL_INTERFACE_LAYER_present_before_activation': 'MKL_INTERFACE_LAYER' in os.environ,
    'conda_activation_attempted_by_diagnosis': False,
    'numeric_code_or_tensors_loaded': False, 'new_jobs_submitted': 0,
}
print(json.dumps(report, sort_keys=True))
PY
