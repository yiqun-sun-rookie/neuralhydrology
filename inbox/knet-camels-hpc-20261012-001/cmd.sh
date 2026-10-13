#!/bin/bash
set -eo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - inbox/knet-camels-hpc-20261012-001/payload/gap_041_20261013_001.tar.gz <<'KNET_GAP_DEPLOY'
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

root = Path('/data1/home/sunyiq/knet_camels_hpc_20261012_001/attempts/gap_041_20261013_001')
payload = Path(sys.argv[1])
expected = '77a3639f89d52730caf0fc4d56abe7ef6e78f491b9003697a4c5d50b2362bacf'
for p in (root, *root.parents, payload, *payload.parents):
    if p.is_symlink():
        raise RuntimeError('linked deployment path')
raw = payload.read_bytes()
assert hashlib.sha256(raw).hexdigest() == expected
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

KNET_GAP_DEPLOY
