"""Login-node file staging and one idempotent sbatch submission only."""
import os
import sys
import io
import json
import re
import hashlib
import tarfile
import subprocess
import datetime
from pathlib import Path

root = Path('/data1/home/sunyiq/knet_camels_hpc_20261012_001/attempts/state_channel_diag_20261016_001_scopefix001')
payload = Path(sys.argv[1])
expected = '616c4afb25f3a5dc1400c3aadde89a080fa0fe2c367234adfe79c1554446ef49'
for p in (root, *root.parents, payload, *payload.parents):
    if p.is_symlink():
        raise RuntimeError('linked deployment path')
raw = payload.read_bytes()
assert hashlib.sha256(raw).hexdigest() == expected
oldroot=Path('/data1/home/sunyiq/knet_camels_hpc_20261012_001/attempts/state_channel_diag_20261016_001')
failure=json.loads((oldroot/'runs/02092500/attempt_001/receipt.json').read_bytes())
assert failure['status']=='FAILED' and not failure['result_present']
assert hashlib.sha256((oldroot/'runs/02092500/attempt_001/receipt.json').read_bytes()).hexdigest()=='a0f76a93d42e40b36b958cdc5836486fa99c57e6fde7705d8d58628a2f01bee6'
assert not (oldroot/'runs/04105700/attempt_001/controller_started.json').exists()
state=subprocess.run(['squeue','-j','243676','-h'],capture_output=True,text=True)
assert state.returncode in (0,1) and not state.stdout.strip(),'Original diagnostic must be terminal before technical continuation'

root.mkdir(parents=True, exist_ok=True)
with tarfile.open(fileobj=io.BytesIO(raw), mode='r:gz') as tar:
    for member in tar.getmembers():
        rel = Path(member.name)
        assert member.isfile() and not rel.is_absolute() and '..' not in rel.parts
        path = root / rel
        assert not path.is_symlink()
        content = tar.extractfile(member).read()
        path.parent.mkdir(parents=True, exist_ok=True)
        if path.exists():
            assert path.read_bytes() == content, 'existing deployment differs'
        else:
            with path.open('xb') as handle:
                handle.write(content)
manifest = json.loads((root / 'deployment_manifest.json').read_bytes())
for entry in manifest['files']:
    path = root / entry['path']
    assert hashlib.sha256(path.read_bytes()).hexdigest() == entry['sha256']
for entry in manifest['files']:
    if entry['path'].endswith('.py'):
        compile((root / entry['path']).read_bytes(), entry['path'], 'exec')
assert b'\r' not in (root / 'diagnostic.slurm').read_bytes()
(root / 'logs').mkdir(exist_ok=True)
submission = root / 'submission.json'
if submission.exists():
    print('SUBMISSION_JSON=' + submission.read_text())
else:
    started = root / 'submission_started.json'
    with started.open('x') as handle:
        json.dump(dict(utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                       archive_sha256=expected, submission_replay_forbidden=True), handle)
        handle.flush()
        os.fsync(handle.fileno())
    preflight=subprocess.run([sys.executable,'-u','-B',str(root/'registry_preflight.py')],cwd=str(root),capture_output=True,text=True)
    print(preflight.stdout,flush=True)
    assert preflight.returncode==0,preflight.stdout+preflight.stderr
    snapshot = subprocess.run(['sinfo', '-p', 'hgpu4', '-N', '-h', '-o', '%N|%T|%C'], capture_output=True, text=True)
    reply = subprocess.run(['sbatch', str(root / 'diagnostic.slurm')], capture_output=True, text=True)
    text = reply.stdout + reply.stderr
    (root / 'submission_stdout.txt').write_text(text)
    matches = re.findall(r'Submitted batch job ([0-9]+)', text)
    assert reply.returncode == 0 and len(matches) == 1, 'submission outcome needs inspection; do not retry blindly'
    record = dict(status='SUBMITTED', job_id=matches[0], remote_root=str(root),
                  submitted_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                  sbatch_reply=text, partition_snapshot=snapshot.stdout,
                  archive_sha256=expected, source_files_verified=len(manifest['files']))
    with submission.open('x') as handle:
        json.dump(record, handle, indent=2)
    print('SUBMISSION_JSON=' + json.dumps(record))
