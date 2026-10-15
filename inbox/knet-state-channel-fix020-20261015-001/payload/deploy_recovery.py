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

root = Path('/data1/home/sunyiq/knet_camels_hpc_20261012_001/attempts/state_channel_finetune_20261015_001_startup_fix020')
payload = Path(sys.argv[1])
expected = '73de9b8d3abbc91038bf17e19e1c35b277584cf75bb125365efd506462ad8f7c'
for p in (root, *root.parents, payload, *payload.parents):
    if p.is_symlink():
        raise RuntimeError('linked deployment path')
raw = payload.read_bytes()
assert hashlib.sha256(raw).hexdigest() == expected
# Verify the preserved zero-update failure before staging or submitting.
original = Path('/data1/home/sunyiq/knet_camels_hpc_20261012_001/attempts/state_channel_finetune_20261015_001')
def original_bytes(relative, expected_hash):
    path = original / relative
    for p in (path, *path.parents):
        assert not p.is_symlink()
    data = path.read_bytes()
    assert hashlib.sha256(data).hexdigest() == expected_hash
    return data
old_identity = json.loads(original_bytes('submission.json', '724b18f09285fa7fe2fbf53ab015af3ae053d6f53ce7be0396bbdf37586aa0f8'))
assert old_identity['job_id'] == '242768'
original_bytes('plan_contract.json', 'e881c0da2b2181984598ac668696402f32d65b531d4060f5f018dde183137d6d')
original_bytes('worker.py', 'b5d9430b6cddc17d7556dd68580f239e24f6b46f8092d4a6d3dee64d123b7806')
failed = json.loads(original_bytes('runs/02092500/attempt_001/receipt.json', 'bc4c36ca002c8e7a4b3339718e03e0cfa3a035fd86576a3379b7915f37585c69'))
original_bytes('runs/02092500/attempt_001/stdout.log', '0d22fcb627db8c3d2a922e844622b664c4726f7f03fca87e71e06cde86f06753')
assert failed['status']=='FAILED' and failed['total_optimizer_calls'] is None and not failed['result_present']
assert not (original/'runs/02092500/attempt_001/result.json').exists()
assert not (original/'runs/02092500/attempt_001/initialization_gate.json').exists()
accounting = subprocess.run(['sacct','-j','242768','-n','-P','--format=JobID,State'], capture_output=True, text=True, check=True).stdout
assert any(line.split('|')[:2] == ['242768_0','FAILED'] for line in accounting.splitlines())

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
                  archive_sha256=expected, source_files_verified=len(manifest['files']),
                  original_job_id='242768', recovery_basin='02092500', dependency='afterany:242768',
                  original_optimizer_calls=0, remaining_optimizer_calls=40)
    with submission.open('x') as handle:
        json.dump(record, handle, indent=2)
    print('SUBMISSION_JSON=' + json.dumps(record))
