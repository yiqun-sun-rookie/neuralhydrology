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

root = Path('/data1/home/sunyiq/knet_camels_hpc_20261012_001/attempts/state_channel_finetune_20261015_001_startup_fix020_v2')
payload = Path(sys.argv[1])
expected = 'e13fafa525b64701b77caf819b3da9a8eb4dab1fc9c453e617c60f0783216f99'
for p in (root, *root.parents, payload, *payload.parents):
    if p.is_symlink():
        raise RuntimeError('linked deployment path')
raw = payload.read_bytes()
assert hashlib.sha256(raw).hexdigest() == expected
# Validate both preserved zero-update failures before a new, exclusive submission.
failures=[{'job_id': '242768', 'remote_root': '/data1/home/sunyiq/knet_camels_hpc_20261012_001/attempts/state_channel_finetune_20261015_001', 'receipt_sha256': 'bc4c36ca002c8e7a4b3339718e03e0cfa3a035fd86576a3379b7915f37585c69', 'log_sha256': '0d22fcb627db8c3d2a922e844622b664c4726f7f03fca87e71e06cde86f06753', 'scientific_worker_sha256': 'b5d9430b6cddc17d7556dd68580f239e24f6b46f8092d4a6d3dee64d123b7806', 'wall_seconds': 12.102419178932905, 'confirmed_optimizer_calls': 0, 'count_basis': 'Fatal stack precedes network and optimizer construction.'}, {'job_id': '242858', 'remote_root': '/data1/home/sunyiq/knet_camels_hpc_20261012_001/attempts/state_channel_finetune_20261015_001_startup_fix020', 'receipt_sha256': '32cac488450f496eaa50ecb7ba27ed6df01b44da930c401b37aeff0e56bc50df', 'log_sha256': 'a476878459e9bc190f15333ca953db03762a95767b42e1a7c45940f9e28630e7', 'scientific_worker_sha256': '340255dc33084b1b9f64bbada3325505b8e05731ac7e4041a57c73d9407dd0ea', 'wall_seconds': 11.8720329888165, 'confirmed_optimizer_calls': 0, 'count_basis': 'Fatal stack precedes network and optimizer construction.'}]
for failure in failures:
    previous=Path(failure['remote_root'])
    def checked_original(relative,expected_hash):
        path=previous/relative
        for p in (path,*path.parents):assert not p.is_symlink()
        data=path.read_bytes();assert hashlib.sha256(data).hexdigest()==expected_hash
        return data
    result=json.loads(checked_original('runs/02092500/attempt_001/receipt.json',failure['receipt_sha256']))
    checked_original('runs/02092500/attempt_001/stdout.log',failure['log_sha256'])
    checked_original('worker.py',failure['scientific_worker_sha256'])
    assert result['status']=='FAILED' and result['total_optimizer_calls'] is None and not result['result_present']
    assert not (previous/'runs/02092500/attempt_001/result.json').exists()
    assert not (previous/'runs/02092500/attempt_001/initialization_gate.json').exists()
original=Path('/data1/home/sunyiq/knet_camels_hpc_20261012_001/attempts/state_channel_finetune_20261015_001')
completed=json.loads((original/'runs/04105700/attempt_001/receipt.json').read_bytes())
science=json.loads((original/'runs/04105700/attempt_001/result.json').read_bytes())
assert completed['status']=='COMPLETED' and science['status']=='COMPLETE'
assert science['total_optimizer_calls']==40 and all(a['optimizer_calls']==20 for a in science['arms'].values())

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
    preflight = subprocess.run([sys.executable,'-u','-B',str(root/'registry_preflight.py')],cwd=str(root),capture_output=True,text=True)
    (root/'registry_preflight_stdout.txt').write_text(preflight.stdout+preflight.stderr)
    print(preflight.stdout,flush=True)
    assert preflight.returncode==0,'Registry preflight failed before submission; inspect, do not retry blindly'
    snapshot = subprocess.run(['sinfo', '-p', 'hgpu4', '-N', '-h', '-o', '%N|%T|%C'], capture_output=True, text=True)
    reply = subprocess.run(['sbatch', str(root / 'diagnostic.slurm')], capture_output=True, text=True)
    text = reply.stdout + reply.stderr
    (root / 'submission_stdout.txt').write_text(text)
    matches = re.findall(r'Submitted batch job ([0-9]+)', text)
    assert reply.returncode == 0 and len(matches) == 1, 'submission outcome needs inspection; do not retry blindly'
    record = dict(status='SUBMITTED', job_id=matches[0], remote_root=str(root),
                  submitted_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                  sbatch_reply=text, partition_snapshot=snapshot.stdout,
                  archive_sha256=expected, source_files_verified=len(manifest['files']),original_job_id='242768',previous_recovery_job_id='242858',
                  recovery_basin='02092500',dependency='afterany:242768',original_optimizer_calls=0,
                  remaining_optimizer_calls=40,registry_preflight='PASS')
    with submission.open('x') as handle:
        json.dump(record, handle, indent=2)
    print('SUBMISSION_JSON=' + json.dumps(record))
