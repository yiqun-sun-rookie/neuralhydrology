"""Exclusive deployment and bounded submission; no tensor loading or login-node training."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import tarfile
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath

ROOT = Path('/data1/home/sunyiq/kalmannet_wrr_lr_stability_20260914')
SOURCE_DATA = Path('/data1/home/sunyiq/kalmannet_wrr_hp_extension_20260902/repo/data/processed/high_flow_aug')
DATA_NAMES = {'train': 'train_win800_19990101_01-20070527_03.pt',
              'val': 'val_win800_20070527_04-20090314_13.pt'}


def sha(path):
    result = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1 << 20), b''):
            result.update(block)
    return result.hexdigest()


def write_new(path, raw):
    with path.open('xb') as stream:
        stream.write(raw)


def receipt(path, obj):
    write_new(path, (json.dumps(obj, indent=2, sort_keys=True) + '\n').encode())


def unpack_new(archive_path, root, manifest):
    if os.path.lexists(root):
        raise FileExistsError(f'no overwrite or retry: {root}')
    if sha(archive_path) != manifest['archive']['sha256'] or archive_path.stat().st_size != manifest['archive']['size_bytes']:
        raise ValueError('archive identity mismatch')
    expected = manifest['static_files']
    with tarfile.open(archive_path, 'r:gz') as archive:
        members = archive.getmembers()
        names = []
        for member in members:
            name = member.name
            relative = PurePosixPath(name)
            if (not name or relative.is_absolute() or '..' in relative.parts or '\\' in name
                    or ':' in name or relative.as_posix() != name or name == '.' or not member.isfile()):
                raise ValueError(f'unsafe archive member: {name}')
            names.append(name)
        if len(names) != len(set(names)) or set(names) != set(expected):
            raise ValueError('archive membership mismatch')
        # Verify every member before claiming or writing a deployment directory.
        for member in members:
            if hashlib.sha256(archive.extractfile(member).read()).hexdigest() != expected[member.name]:
                raise ValueError(f'archive member hash mismatch: {member.name}')
        root.mkdir()
        for member in members:
            target = root.joinpath(*PurePosixPath(member.name).parts)
            target.parent.mkdir(parents=True, exist_ok=True)
            write_new(target, archive.extractfile(member).read())
    for name, expected_hash in expected.items():
        if sha(root / name) != expected_hash:
            raise ValueError(f'deployed member mismatch: {name}')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--payload', type=Path, required=True)
    parser.add_argument('--submit', action='store_true')
    args = parser.parse_args()
    if not args.submit:
        raise SystemExit('explicit --submit required for this ten-run authorization')
    payload = args.payload.resolve()
    manifest_raw = (payload / 'PACKAGE_MANIFEST.json').read_bytes()
    manifest = json.loads(manifest_raw)
    if manifest['remote_root'] != str(ROOT) or manifest['allowed_indices'] != list(range(10)):
        raise ValueError('deployment contract mismatch')
    if manifest['retry_authorized'] or manifest['test_split_authorized']:
        raise ValueError('forbidden authorization')
    sources = {split: SOURCE_DATA / name for split, name in DATA_NAMES.items()}
    if not all(path.is_file() for path in sources.values()):
        raise ValueError('one of the two frozen training/validation data files is absent')
    unpack_new(payload / 'study.tar.gz', ROOT, manifest)
    write_new(ROOT / 'PACKAGE_MANIFEST.json', manifest_raw)
    (ROOT / 'logs').mkdir()
    data_dir = ROOT / 'repo/data/processed/high_flow_aug'
    data_dir.mkdir(parents=True)
    for source in sources.values():
        (data_dir / source.name).symlink_to(source)
    receipt(ROOT / 'DEPLOYMENT_RECEIPT.json', {
        'stage': 'SOURCE_DEPLOYED', 'root': str(ROOT),
        'archive_sha256': manifest['archive']['sha256'],
        'static_files_verified': len(manifest['static_files']),
        'data_links': {split: str(path) for split, path in sources.items()},
        'data_hash_verification': 'required by frozen launcher on each compute task before loading',
        'time_utc': datetime.now(timezone.utc).isoformat(), 'optimizer_steps_on_login_node': 0})
    command = ['sbatch', '--parsable', str(ROOT / 'hpc_array.slurm')]
    receipt(ROOT / 'SUBMISSION_INTENT.json', {'command': command, 'array': '0-9%6',
            'time_utc': datetime.now(timezone.utc).isoformat(), 'retry_authorized': False})
    response = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, check=False)
    result = {'returncode': response.returncode, 'stdout': response.stdout, 'stderr': response.stderr}
    receipt(ROOT / 'SUBMISSION_RESPONSE.json', result)
    match = re.fullmatch(r'([0-9]+)(?:;[^\s;]+)?', response.stdout.strip())
    if response.returncode != 0 or match is None:
        raise RuntimeError(f'submission failed or uncertain; do not retry: {result}')
    job_id = match.group(1)
    write_new(ROOT / 'array_job_id.txt', job_id.encode('ascii'))
    print(json.dumps({'stage': 'SUBMITTED', 'job_id': job_id, 'array': '0-9%6',
                      'root': str(ROOT), 'time_utc': datetime.now(timezone.utc).isoformat()}), flush=True)
    subprocess.run(['squeue', '-j', job_id, '-o', '%i|%j|%T|%P|%M|%R'], check=True)


if __name__ == '__main__':
    main()
