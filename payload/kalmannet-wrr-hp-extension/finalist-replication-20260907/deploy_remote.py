"""One-time deployment/submission. Run by mailbox on the login node; no training here."""
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

ROOT = Path('/data1/home/sunyiq/kalmannet_wrr_finalist_replication_20260907')
OLD_ROOT = Path('/data1/home/sunyiq/kalmannet_wrr_hp_extension_20260902')
EXP_REL = Path('experiments/optimize_hyper_parameters/wrr_hp_extension_20260902')


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as fh:
        for b in iter(lambda: fh.read(1 << 20), b''):
            h.update(b)
    return h.hexdigest()


def write_new(path: Path, data: bytes) -> None:
    with path.open('xb') as fh:
        fh.write(data)


def write_json(path: Path, obj: dict) -> None:
    write_new(path, (json.dumps(obj, indent=2) + '\n').encode('utf-8'))


def safe_relative(name: str) -> PurePosixPath:
    rel = PurePosixPath(name)
    if not name or rel.is_absolute() or '..' in rel.parts or '\\' in name or rel.as_posix() != name or name == '.':
        raise ValueError(f'Unsafe package path: {name}')
    return rel


def verify_static(root: Path, expected: dict[str, str]) -> dict[str, str]:
    checked = {}
    for name, digest in expected.items():
        rel = safe_relative(name)
        target = root.joinpath(*rel.parts)
        if target.is_symlink() or not target.is_file() or not target.resolve().is_relative_to(root.resolve()):
            raise ValueError(f'Invalid static file: {target}')
        actual = sha256(target)
        if actual != digest:
            raise ValueError(f'SHA256 mismatch for {target}: expected {digest}, got {actual}')
        checked[name] = actual
    return checked


def extract_new_tree(archive: Path, root: Path, expected_members: set[str]) -> None:
    if root.exists() or root.is_symlink():
        raise FileExistsError(f'Deployment target already exists: {root}')
    with tarfile.open(archive, 'r:gz') as tf:
        members = tf.getmembers()
        names = []
        for member in members:
            safe_relative(member.name)
            if not member.isfile():
                raise ValueError(f'Non-regular package member: {member.name}')
            names.append(member.name)
        if len(set(names)) != len(names):
            raise ValueError('Duplicate archive members')
        if set(names) != expected_members:
            raise ValueError('Archive and manifest member lists differ')
        root.mkdir()  # Atomic ownership; never merge into an existing directory.
        for member in members:
            target = root / member.name
            target.parent.mkdir(parents=True, exist_ok=True)
            source = tf.extractfile(member)
            if source is None:
                raise ValueError(f'Cannot read archive member: {member.name}')
            with source, target.open('xb') as dest:
                for block in iter(lambda: source.read(1 << 20), b''):
                    dest.write(block)


def old_fingerprints(baseline: dict, source_manifest: dict) -> dict[str, str]:
    repo = OLD_ROOT / 'repo'
    expected = dict(source_manifest['source_sha256'])
    expected[(EXP_REL / 'source_manifest.json').as_posix()] = baseline['old_manifest_sha256']
    for reference in baseline['references']:
        cell = Path(reference['cell_path'])
        audit = Path(reference['audit']['path'])
        for path, digest in [(cell, reference['cell_sha256']),
                             (cell.parent / 'results/best_model.pt', reference['checkpoint_sha256']),
                             (audit, reference['audit']['sha256'])]:
            rel = path.relative_to(repo).as_posix()
            expected[rel] = digest
    return verify_static(repo, expected)


def verify_data(baseline: dict) -> None:
    if set(baseline['data']) != {'train', 'val'}:
        raise ValueError('Only training and validation links are allowed')
    for split, entry in baseline['data'].items():
        path = Path(entry['path'])
        required_parent = OLD_ROOT / 'repo/data/processed/high_flow_aug'
        if path.parent != required_parent or not path.name.startswith(split + '_'):
            raise ValueError(f'Unexpected {split} source path: {path}')
        if path.stat().st_size != entry['bytes'] or sha256(path) != entry['sha256']:
            raise ValueError(f'Data contract mismatch: {split}')


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--payload', type=Path, required=True)
    parser.add_argument('--submit', action='store_true')
    args = parser.parse_args()
    if not args.submit:
        raise SystemExit('Deployment and six-task submission require explicit --submit')
    payload = args.payload.resolve()
    manifest_bytes = (payload / 'PACKAGE_MANIFEST.json').read_bytes()
    manifest = json.loads(manifest_bytes)
    baseline = json.loads((payload / 'REMOTE_BASELINE.json').read_bytes())
    old_manifest_bytes = (payload / 'REMOTE_SOURCE_MANIFEST.json').read_bytes()
    old_manifest = json.loads(old_manifest_bytes)
    if Path(manifest['remote_root']) != ROOT or baseline['new_root'] != str(ROOT):
        raise ValueError('Root identity mismatch')
    if ROOT.exists() or ROOT.is_symlink():
        raise FileExistsError(f'No overwrite or resubmit: {ROOT}')
    if hashlib.sha256(old_manifest_bytes).hexdigest() != baseline['old_manifest_sha256']:
        raise ValueError('Original manifest fingerprint mismatch')
    relative_archive = safe_relative(manifest['archive']['relative_path'])
    archive = payload.joinpath(*relative_archive.parts)
    if sha256(archive) != manifest['archive']['sha256'] or archive.stat().st_size != manifest['archive']['size_bytes']:
        raise ValueError('Archive fingerprint mismatch')
    before = old_fingerprints(baseline, old_manifest)
    verify_data(baseline)
    extract_new_tree(archive, ROOT, set(manifest['static_files']))
    write_new(ROOT / 'PACKAGE_MANIFEST.json', manifest_bytes)
    write_json(ROOT / 'OLD_FINGERPRINTS_BEFORE.json', before)
    write_json(ROOT / 'REMOTE_BASELINE.json', baseline)
    write_new(ROOT / 'REMOTE_SOURCE_MANIFEST.json', old_manifest_bytes)
    (ROOT / 'logs').mkdir()
    data_dir = ROOT / 'repo/data/processed/high_flow_aug'
    data_dir.mkdir(parents=True)
    for entry in baseline['data'].values():
        target = data_dir / Path(entry['path']).name
        target.symlink_to(entry['path'])
        if sha256(target) != entry['sha256']:
            raise ValueError(f'Linked data mismatch: {target}')
    deployed = verify_static(ROOT, manifest['static_files'])
    inner_manifest = json.loads((ROOT / 'repo' / EXP_REL / 'source_manifest.json').read_bytes())
    inner_checked = verify_static(ROOT / 'repo', inner_manifest['source_sha256'])
    after = old_fingerprints(baseline, old_manifest)
    if before != after:
        raise ValueError('Original evidence changed during deployment')
    receipt = {'stage': 'DEPLOYMENT_PASS', 'root': str(ROOT), 'archive_sha256': sha256(archive),
               'static_files_verified': len(deployed), 'source_files_verified': len(inner_checked),
               'old_files_unchanged': len(after), 'data_splits': ['train', 'val'],
               'optimizer_steps_during_deployment': 0,
               'time_utc': datetime.now(timezone.utc).isoformat()}
    write_json(ROOT / 'DEPLOYMENT_RECEIPT.json', receipt)
    print(json.dumps(receipt), flush=True)
    command = ['sbatch', '--parsable', str(ROOT / 'hpc_array.slurm')]
    write_json(ROOT / 'SUBMISSION_INTENT.json', {'command': command, 'array': '0-5%6',
        'time_utc': datetime.now(timezone.utc).isoformat(), 'retry_authorized': False})
    response = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, check=False)
    submission = {'returncode': response.returncode, 'stdout': response.stdout, 'stderr': response.stderr}
    write_json(ROOT / 'SUBMISSION_RESPONSE.json', submission)
    match = re.fullmatch(r'([0-9]+)(?:;[^\s;]+)?', response.stdout.strip())
    if response.returncode or match is None:
        raise RuntimeError(f'Submission failed or uncertain; do not retry: {submission}')
    job_id = match.group(1)
    write_new(ROOT / 'array_job_id.txt', job_id.encode('ascii'))
    print(json.dumps({'stage': 'SUBMITTED', 'job_id': job_id, 'array': '0-5%6', 'root': str(ROOT)}), flush=True)
    subprocess.run(['squeue', '-j', job_id, '-o', '%i|%j|%T|%P|%M|%R'], check=False)


if __name__ == '__main__':
    main()
