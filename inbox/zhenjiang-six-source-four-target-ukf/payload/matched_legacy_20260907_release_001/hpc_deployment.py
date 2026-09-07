#!/usr/bin/env python3
"""Build a deterministic code-only release; deploy once using the school wrapper.

Examples (controller only):
  python -B hpc_deployment.py build --release-dir artifacts/release_001 --version matched_20260907_001
  python -B hpc_deployment.py deploy --archive PATH --manifest PATH --manifest-sha256 SHA
The deploy/job commands accept no output-root or scheduler override. No numerical
package is imported here. Formal data are opened only by the frozen seed entry.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import gzip
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess
import tarfile
import time


PROJECT = Path(__file__).resolve().parent
REMOTE_ROOT = '/data1/home/sunyiq/zhenjiang_matched_legacy_process_20260907_001'
SOURCE_ROOT = Path('G:/github/pycharm/projects/zhenjiang_stage_forecast')
SOURCE_CONTRACT = SOURCE_ROOT / 'docs/records/zhenjiang_stage_a_recovery_20260905_001_data_contract.json'
CONDA_SH = '/data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh'
WRAPPER = Path('/usr/local/globle/softs/slurm/19.05.4.1/bin/xbatch')
FAMILY = 'ZHENJIANG_MATCHED_LEGACY_PROCESS_MODEL_20260907'
CONTRACT_SHA = 'd52fea4d1400fa00a78d9842cc1cf38e292bd31dfc98e19ab8529d1c62234de1'
REFERENCE_SHA = '3eaa238f8f2c3bb40d1ce3aa201c49a90608c5af2d97ee337724c1a239a6f7ee'
FIXED_HASHES = {
    'app/matched_formal.py': 'f581802c3609218889031ded1c41996abbc198e1c9c63389c1c7356c579f7f95',
    'app/matched_training.py': '3bcad7b87ce10286f1e1d4a7b5fad6cf93139ee14ae40cef0e063b04ced6bd3c',
    'app/matched_legacy_model.py': 'ed29c68b853e48e5d1d78099fc0b62e2d81419cee76c4d1ca498d995626eb586',
    'contracts/execution_contract.json': CONTRACT_SHA,
    'contracts/reference_source_manifest.json': REFERENCE_SHA,
    'contracts/source_data_contract.json': '0e2cc530d5158cb9535862b10d6489436b73811c84a3d601579ed79de28155b3',
    'contracts/comparison_protocol.json': 'c1993098b3ee7c936bcc77cb5ae2e5e99c4dd13e45eb17ce23f7835d2217bd43',
    'contracts/data_authorization.json': 'c9212baf300c20b4e176f38538b57efb41d105f7b08b538f8c8788724681fe74',
    'contracts/paid_execution_authorization.json': '2670bf92688b8735599b35f4499721157b60a17e936ccb53897c1d8a0c9cd16a',
}
RELEASE_FILES = {'code.tar.gz', 'bundle_manifest.json', 'hpc_deployment.py', 'cmd.sh', 'payload_manifest.json'}


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def identity(data):
    return {'byte_count': len(data), 'sha256': sha256(data)}


def json_bytes(value):
    return (json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + '\n').encode('utf-8')


def parse_json(raw):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError('duplicate JSON key')
            result[key] = value
        return result
    return json.loads(raw, object_pairs_hook=unique)


def utc_now():
    return datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')


def safe_name(name):
    if not isinstance(name, str) or not name or '\\' in name or '\x00' in name:
        raise ValueError('unsafe path')
    parsed = PurePosixPath(name)
    if parsed.is_absolute() or ':' in name or str(parsed) != name or any(
            part in ('', '.', '..') for part in name.split('/')):
        raise ValueError('unsafe path')
    return name


def reject_parent_components(path):
    """Check lexical components without following or inspecting any filesystem path."""
    path = Path(path)
    if '..' in path.parts:
        raise ValueError('explicit parent-directory components are forbidden')
    return path


def ordinary_path(path, *, allow_missing=False):
    """Reject redirected components, including Windows junctions/reparse points."""
    path = reject_parent_components(path).absolute()
    for item in reversed((path,) + tuple(path.parents)):
        if not item.exists() and not item.is_symlink():
            if allow_missing:
                continue
            raise ValueError('missing ordinary path')
        info = item.lstat()
        if stat.S_ISLNK(info.st_mode) or getattr(info, 'st_file_attributes', 0) & 1024:
            raise ValueError('redirected path')
    return path


def read_regular(path, maximum=8_000_000):
    path = ordinary_path(path)
    if not path.is_file() or path.stat().st_size > maximum:
        raise ValueError('not a bounded regular file')
    return path.read_bytes()


def exclusive_bytes(path, data):
    """Persist evidence before returning; never replace an existing path."""
    with Path(path).open('xb') as handle:
        handle.write(data)
        handle.flush()
        os.fsync(handle.fileno())
    if os.name != 'nt':
        descriptor = os.open(str(Path(path).parent), os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(descriptor)
        finally:
            os.close(descriptor)


def exclusive_json(path, value):
    exclusive_bytes(path, json_bytes(value))


def allowed_archive_names(references):
    paths = [safe_name(item['relative_path']) for item in references['files']]
    if len(paths) != 10 or len(set(paths)) != 10:
        raise ValueError('reference allow-list must have ten unique files')
    return set(FIXED_HASHES) | {'hpc/matched_legacy.slurm', 'hpc_deployment.py'} | {
        'app/reference/' + name for name in paths}


def validate_files(files):
    for name, expected in FIXED_HASHES.items():
        if name not in files or sha256(files[name]) != expected:
            raise ValueError('frozen file identity differs: ' + name)
    references = parse_json(files['contracts/reference_source_manifest.json'])
    if set(files) != allowed_archive_names(references):
        raise ValueError('archive contains missing or unlisted sources')
    for item in references['files']:
        if identity(files['app/reference/' + item['relative_path']]) != {
                'sha256': item['sha256'], 'byte_count': item['byte_count']}:
            raise ValueError('reference source identity differs')
    for name in ('hpc/matched_legacy.slurm', 'hpc_deployment.py'):
        if b'\r' in files[name]:
            raise ValueError('new code must be LF only')


def validate_bundle(archive, manifest_bytes):
    """Validate the complete archive in memory before creating any output path."""
    manifest = parse_json(manifest_bytes)
    if set(manifest) != {'schema_version', 'execution_contract_sha256', 'remote_root', 'archive', 'files'}:
        raise ValueError('bundle manifest keys differ')
    if (manifest['schema_version'] != 1 or manifest['remote_root'] != REMOTE_ROOT
            or manifest['execution_contract_sha256'] != CONTRACT_SHA
            or manifest['archive'] != identity(archive) or len(archive) > 8_000_000):
        raise ValueError('bundle manifest identity differs')
    if not isinstance(manifest['files'], dict) or len(manifest['files']) != 21:
        raise ValueError('bundle file count differs')
    files = {}
    total = 0
    with tarfile.open(fileobj=io.BytesIO(archive), mode='r:gz') as source:
        for member in source:
            safe_name(member.name)
            total += member.size
            if (not member.isfile() or member.name in files or member.name not in manifest['files']
                    or member.size < 0 or total > 8_000_000 or member.pax_headers):
                raise ValueError('unsafe or duplicate archive member')
            data = source.extractfile(member).read()
            if manifest['files'][member.name] != identity(data):
                raise ValueError('archive member identity differs')
            files[member.name] = data
    if set(files) != set(manifest['files']):
        raise ValueError('archive member list differs')
    validate_files(files)
    return files


def deployment_command(version, payload):
    hashes = {name: identity(payload[name]) for name in
              ('hpc_deployment.py', 'code.tar.gz', 'bundle_manifest.json')}
    # The runner stages only cmd.sh. Payloads are read from its real mailbox checkout.
    return ("#!/usr/bin/env bash\nset -e -o pipefail\numask 077\n"
            "export PYTHONDONTWRITEBYTECODE=1\n"
            f'payload="${{HOME}}/hpc_mailbox/inbox/zhenjiang-six-source-four-target-ukf/payload/{version}"\n'
            'python3 -B - "$payload" <<\'PY\'\n'
            'import hashlib, pathlib, runpy, sys\n'
            'root = pathlib.Path(sys.argv[1])\n'
            f'expected = {hashes!r}\n'
            'for name, spec in expected.items():\n'
            '    path = root / name\n'
            '    if path.is_symlink() or not path.is_file(): raise SystemExit("invalid payload")\n'
            '    data = path.read_bytes()\n'
            '    if len(data) != spec["byte_count"] or hashlib.sha256(data).hexdigest() != spec["sha256"]:\n'
            '        raise SystemExit("payload identity differs")\n'
            'sys.argv = [str(root / "hpc_deployment.py"), "deploy", "--archive", str(root / "code.tar.gz"),\n'
            '            "--manifest", str(root / "bundle_manifest.json"), "--manifest-sha256",\n'
            '            expected["bundle_manifest.json"]["sha256"]]\n'
            'runpy.run_path(str(root / "hpc_deployment.py"), run_name="__main__")\n'
            'PY\n').encode('utf-8')


def pack_archive(files):
    """Deterministic raw-byte archive primitive, also used by synthetic CRLF tests."""
    tar_bytes = io.BytesIO()
    with tarfile.open(fileobj=tar_bytes, mode='w', format=tarfile.USTAR_FORMAT) as archive:
        for name in sorted(files):
            safe_name(name)
            entry = tarfile.TarInfo(name)
            entry.size = len(files[name])
            entry.mode = 0o644
            entry.uid = entry.gid = entry.mtime = 0
            entry.uname = entry.gname = ''
            archive.addfile(entry, io.BytesIO(files[name]))
    buffer = io.BytesIO()
    with gzip.GzipFile(filename='', mode='wb', fileobj=buffer, mtime=0, compresslevel=9) as compressed:
        compressed.write(tar_bytes.getvalue())
    return buffer.getvalue()


def build_release(project, release_dir, version):
    reject_parent_components(release_dir)
    project = ordinary_path(project)
    release_dir = ordinary_path(release_dir, allow_missing=True)
    if project != PROJECT or project / 'artifacts' not in release_dir.parents:
        raise ValueError('release must be a new child under this project artifacts')
    if not re.fullmatch(r'[a-z][a-z0-9_]{0,79}', version):
        raise ValueError('invalid version')
    if release_dir.exists():
        raise FileExistsError('release already exists')
    files = {}
    for name in FIXED_HASHES:
        if name == 'contracts/source_data_contract.json':
            path = SOURCE_CONTRACT
        elif name == 'contracts/comparison_protocol.json':
            path = project / 'comparison_protocol.json'
        elif name.startswith('app/'):
            path = project / name[4:]
        else:
            path = project / name
        files[name] = read_regular(path)
    references = parse_json(files['contracts/reference_source_manifest.json'])
    if sha256(files['contracts/reference_source_manifest.json']) != REFERENCE_SHA:
        raise ValueError('frozen reference manifest differs')
    for item in references['files']:
        name = safe_name(item['relative_path'])
        files['app/reference/' + name] = read_regular(SOURCE_ROOT / name)
    for name in ('hpc/matched_legacy.slurm', 'hpc_deployment.py'):
        files[name] = read_regular(project / name)
    validate_files(files)
    archive = pack_archive(files)
    manifest = json_bytes({'schema_version': 1, 'remote_root': REMOTE_ROOT,
                           'execution_contract_sha256': CONTRACT_SHA, 'archive': identity(archive),
                           'files': {name: identity(data) for name, data in sorted(files.items())}})
    validate_bundle(archive, manifest)
    payload = {'code.tar.gz': archive, 'bundle_manifest.json': manifest,
               'hpc_deployment.py': files['hpc_deployment.py']}
    payload['cmd.sh'] = deployment_command(version, payload)
    payload['payload_manifest.json'] = json_bytes({
        'schema_version': 1, 'kind': 'deployment', 'version': version,
        'execution_contract_sha256': CONTRACT_SHA,
        'files': {name: identity(data) for name, data in sorted(payload.items())}})
    # All validation precedes the first write; exclusive directory is the release reservation.
    release_dir.mkdir()
    for name, data in sorted(payload.items()):
        exclusive_bytes(release_dir / name, data)
    return release_dir


def submission_receipt(job_id):
    return {'schema_version': 1, 'experiment_family': FAMILY, 'status': 'submitted',
            'job_id': job_id, 'execution_contract_sha256': CONTRACT_SHA,
            'submission_attempt_number': 1, 'maximum_sbatch_submissions': 1,
            'submitted_at_utc': utc_now()}


def _deploy_to_root(root, archive, manifest_bytes, runner=subprocess.run, *, wrapper=WRAPPER):
    """Internal filesystem adapter; public deploy fixes root and wrapper absolutely."""
    root = ordinary_path(root, allow_missing=True)
    if root.exists():
        raise FileExistsError('remote root already exists; no replay')
    files = validate_bundle(archive, manifest_bytes)
    wrapper = ordinary_path(wrapper)
    if not wrapper.is_file() or not os.access(wrapper, os.X_OK):
        raise ValueError('documented school submission wrapper is not executable')
    root.mkdir()
    for name, data in sorted(files.items()):
        target = root / name
        target.parent.mkdir(parents=True, exist_ok=True)
        exclusive_bytes(target, data)
    for name in ('logs', 'app/artifacts', 'evidence/seed_attempts', 'tmp',
                 'cache/xdg', 'cache/cuda', 'cache/torch'):
        (root / name).mkdir(parents=True, exist_ok=True)
    validate_files({name: read_regular(root / name) for name in files})
    evidence = root / 'evidence'
    exclusive_bytes(evidence / 'bundle_manifest.json', manifest_bytes)
    exclusive_json(evidence / 'deployment_verified.json', {
        'schema_version': 1, 'archive': identity(archive), 'manifest': identity(manifest_bytes),
        'execution_contract_sha256': CONTRACT_SHA, 'verified_at_utc': utc_now()})
    exclusive_json(evidence / 'submission_attempt_001.json', {
        'schema_version': 1, 'status': 'reserved', 'attempt_number': 1,
        'execution_contract_sha256': CONTRACT_SHA, 'reserved_at_utc': utc_now(),
        'wrapper': str(wrapper), 'script': str(root / 'hpc/matched_legacy.slurm')})
    try:
        result = runner([str(wrapper), str(root / 'hpc/matched_legacy.slurm')],
                        cwd=str(root), capture_output=True, timeout=60, check=False)
    except Exception as error:
        exclusive_bytes(evidence / 'submission_stdout.bin', getattr(error, 'stdout', None) or b'')
        exclusive_bytes(evidence / 'submission_stderr.bin', getattr(error, 'stderr', None) or b'')
        exclusive_json(evidence / 'submission_outcome.json', {
            'status': 'uncertain', 'error_type': type(error).__name__, 'at_utc': utc_now()})
        raise RuntimeError('submission uncertain; attempt consumed; never resubmit') from None
    exclusive_bytes(evidence / 'submission_stdout.bin', result.stdout)
    exclusive_bytes(evidence / 'submission_stderr.bin', result.stderr)
    matched = re.fullmatch(rb'Submitted batch job ([0-9]+)\r?\n?', result.stdout)
    if result.returncode != 0 or matched is None:
        exclusive_json(evidence / 'submission_outcome.json', {
            'status': 'uncertain', 'returncode': result.returncode, 'at_utc': utc_now()})
        raise RuntimeError('submission response invalid; uncertain; never resubmit')
    receipt = submission_receipt(matched.group(1).decode('ascii'))
    # Atomic visibility prevents a compute-node race observing a partially written JSON receipt.
    staging = evidence / 'submission_receipt.pending.json'
    exclusive_json(staging, receipt)
    os.link(staging, evidence / 'submission_receipt.json')
    if os.name != 'nt':
        descriptor = os.open(str(evidence), os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
    return receipt


def _start_job(root, env, wait_seconds=30):
    ordinary_path(root)
    job_id = env.get('SLURM_JOB_ID', '')
    if (not re.fullmatch(r'[0-9]+', job_id) or env.get('SLURM_RESTART_COUNT', '0') != '0'
            or 'SLURM_ARRAY_TASK_ID' in env or 'SLURM_ARRAY_JOB_ID' in env):
        raise ValueError('invalid job, restart, or array identity')
    receipt_path = root / 'evidence/submission_receipt.json'
    deadline = time.monotonic() + min(max(wait_seconds, 0), 30)
    while not receipt_path.exists() and time.monotonic() < deadline:
        time.sleep(0.1)
    receipt = parse_json(read_regular(receipt_path))
    expected = submission_receipt(job_id)
    if set(receipt) != set(expected) or any(receipt[key] != value for key, value in expected.items()
                                           if key != 'submitted_at_utc'):
        raise ValueError('submission receipt differs')
    timestamp = datetime.fromisoformat(receipt['submitted_at_utc'].replace('Z', '+00:00'))
    if timestamp.tzinfo is None or timestamp.utcoffset().total_seconds() != 0:
        raise ValueError('submission receipt UTC time invalid')
    attempt = ordinary_path(root / 'evidence/job_attempt_001', allow_missing=True)
    attempt.mkdir()
    started = {'schema_version': 1, 'experiment_family': FAMILY, 'status': 'started',
               'job_id': job_id, 'execution_contract_sha256': CONTRACT_SHA,
               'attempt_number': 1, 'started_at_utc': utc_now()}
    exclusive_json(attempt / 'started.json', started)
    return started


def complete_job(root, env):
    job_id = env.get('SLURM_JOB_ID', '')
    started = parse_json(read_regular(root / 'evidence/job_attempt_001/started.json'))
    if started['job_id'] != job_id or started['execution_contract_sha256'] != CONTRACT_SHA:
        raise ValueError('started identity differs')
    completions = {}
    for index, seed in enumerate((17, 29, 43), 1):
        raw = read_regular(root / f'evidence/seed_attempts/seed_{seed}/completion_receipt.json')
        value = parse_json(raw)
        expected = {'schema_version': 1, 'experiment_family': FAMILY, 'status': 'complete',
                    'seed': seed, 'seed_sequence_index': index, 'job_id': job_id,
                    'execution_contract_sha256': CONTRACT_SHA}
        if any(value.get(key) != data for key, data in expected.items()):
            raise ValueError('seed completion receipt differs')
        completions[str(seed)] = identity(raw)
    exclusive_json(root / 'evidence/job_attempt_001/completion_receipt.json', {
        'schema_version': 1, 'status': 'complete', 'job_id': job_id,
        'execution_contract_sha256': CONTRACT_SHA, 'seed_receipts': completions,
        'completed_at_utc': utc_now()})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='action', required=True)
    build = sub.add_parser('build')
    build.add_argument('--release-dir', required=True, type=Path)
    build.add_argument('--version', required=True)
    deploy = sub.add_parser('deploy')
    deploy.add_argument('--archive', required=True, type=Path)
    deploy.add_argument('--manifest', required=True, type=Path)
    deploy.add_argument('--manifest-sha256', required=True)
    sub.add_parser('job-start')
    sub.add_parser('job-complete')
    args = parser.parse_args()
    if args.action == 'build':
        print(build_release(PROJECT, args.release_dir, args.version))
        return
    root = Path(REMOTE_ROOT)
    if os.name != 'posix':
        raise ValueError('formal deployment requires registered POSIX host')
    if args.action == 'deploy':
        if root.exists() or root.is_symlink():
            raise FileExistsError('remote root already exists; no replay')
        manifest = read_regular(args.manifest)
        if sha256(manifest) != args.manifest_sha256:
            raise ValueError('manifest raw byte identity differs')
        print(json.dumps(_deploy_to_root(root, read_regular(args.archive), manifest)))
    else:
        if Path(__file__).resolve() != root / 'hpc_deployment.py':
            raise ValueError('job validator is outside registered root')
        if args.action == 'job-start':
            print(json.dumps(_start_job(root, os.environ)))
        else:
            complete_job(root, os.environ)


if __name__ == '__main__':
    main()
