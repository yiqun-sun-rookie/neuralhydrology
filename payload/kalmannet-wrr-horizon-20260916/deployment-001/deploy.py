"""Login-node-only deployment and exactly-once submission; no tensor imports."""
from __future__ import annotations
import argparse
import hashlib
import io
import importlib.metadata
import json
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import tarfile

REMOTE_ROOT = Path('/data1/home/sunyiq/kalmannet_wrr_training_horizon_20260916')
DATA_SOURCE = Path('/data1/home/sunyiq/kalmannet_wrr_hp_extension_20260902/repo/data/processed/high_flow_aug')
CONFIG = 'experiments/optimize_hyper_parameters/training_horizon_20260916/configs/'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def save_new(path, value):
    with path.open('x', encoding='utf-8') as stream:
        json.dump(value, stream, indent=2)
        stream.write('\n')


def unpack_checked(raw, manifest):
    if sha(raw) != manifest['archive_sha256']:
        raise ValueError('Archive hash mismatch')
    files = {}
    with tarfile.open(fileobj=io.BytesIO(raw), mode='r:gz') as archive:
        for item in archive.getmembers():
            path = PurePosixPath(item.name)
            if (not item.isfile() or path.is_absolute() or '..' in path.parts
                    or '\\' in item.name or item.name in files
                    or item.name not in manifest['files']):
                raise ValueError('Unsafe or unexpected archive member: ' + item.name)
            data = archive.extractfile(item).read()
            if manifest['files'][item.name] != {'sha256': sha(data), 'bytes': len(data)}:
                raise ValueError('Member hash/size mismatch: ' + item.name)
            files[item.name] = data
    if set(files) != set(manifest['files']):
        raise ValueError('Missing archive members')
    return files


def deploy(payload):
    # Reading installed distribution metadata is lightweight; no numerical import.
    environment = {name: importlib.metadata.version(name) for name in ('torch', 'numpy', 'psutil')}
    manifest = json.loads((payload / 'PACKAGE_MANIFEST.json').read_text())
    if manifest['remote_root'] != str(REMOTE_ROOT) or manifest['authorized_seed'] != 42:
        raise ValueError('Wrong deployment target or seed')
    if sha(Path(__file__).read_bytes()) != manifest['deploy_sha256']:
        raise ValueError('Deployment script hash mismatch')
    files = unpack_checked((payload / 'study.tar.gz').read_bytes(), manifest)
    common = json.loads(files[CONFIG + 'common.json'])
    for split, spec in common['data'].items():
        source = DATA_SOURCE / Path(spec['path']).name
        if source.stat().st_size != spec['bytes'] or sha(source.read_bytes()) != spec['sha256']:
            raise ValueError('Source data mismatch: ' + split)
    # Atomic exclusive claim: even a partial failed deployment cannot be reused.
    REMOTE_ROOT.mkdir(exist_ok=False)
    repo = REMOTE_ROOT / 'repo'
    repo.mkdir()
    (REMOTE_ROOT / 'logs').mkdir()
    save_new(REMOTE_ROOT / 'PACKAGE_MANIFEST.json', manifest)
    save_new(REMOTE_ROOT / 'environment_metadata_before_submission.json', environment)
    shutil.copyfile(__file__, REMOTE_ROOT / 'deploy_snapshot.py')
    for relative, data in files.items():
        path = repo / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open('xb') as stream:
            stream.write(data)
    (repo / 'data').mkdir()
    for split, spec in common['data'].items():
        target = Path(spec['path'])
        if target.parent != repo / 'data':
            raise ValueError('Data target outside private deployment')
        with target.open('xb') as stream:
            stream.write((DATA_SOURCE / target.name).read_bytes())
        if sha(target.read_bytes()) != spec['sha256']:
            raise ValueError('Copied data mismatch: ' + split)
        target.chmod(0o444)
    subprocess.run(['git', 'init'], cwd=repo, check=True)
    subprocess.run(['git', 'config', 'core.autocrlf', 'false'], cwd=repo, check=True)
    subprocess.run(['git', 'add', '--', *sorted(files)], cwd=repo, check=True)
    subprocess.run(['git', '-c', 'user.name=Horizon deployment', '-c',
                    'user.email=horizon-deployment@localhost', 'commit', '-m',
                    'Isolated hash-pinned training horizon deployment'], cwd=repo, check=True)
    job_script = repo / 'scripts/hpc_training_horizon/job.slurm'
    if b'\r' in job_script.read_bytes():
        raise ValueError('Slurm script must use LF')
    save_new(REMOTE_ROOT / 'submission_intent.json', {'script': str(job_script),
             'seed': 42, 'no_retry': True, 'probe_gate_before_pair': True})
    result = subprocess.run(['sbatch', str(job_script)], cwd=repo, text=True,
                            capture_output=True, timeout=60)
    receipt = {'returncode': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr}
    save_new(REMOTE_ROOT / 'submission_result.json', receipt)
    matches = re.findall(r'^Submitted batch job ([0-9]+)\s*$', result.stdout, re.MULTILINE)
    if result.returncode != 0 or len(matches) != 1:
        raise RuntimeError('Submission not confirmed; preserve evidence and do not resubmit')
    receipt['job_id'] = int(matches[0])
    save_new(REMOTE_ROOT / 'submission_confirmed.json', receipt)
    print(json.dumps(receipt, indent=2), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('payload', type=Path)
    deploy(parser.parse_args().payload.resolve())
