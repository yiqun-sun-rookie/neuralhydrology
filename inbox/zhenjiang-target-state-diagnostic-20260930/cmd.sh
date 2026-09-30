#!/bin/bash
set -euo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -I -B - <<'ZJ_TARGET_STATUS'
"""Template for bounded read-only monitoring of this 24-run array.

Builder substitutes the unique job ID. Reads only the registered directory,
its source files, and that job's scheduling/accounting status. No mutation.
"""
import hashlib
import json
import math
from pathlib import Path
import subprocess
import time

ROOT = Path('/data1/home/sunyiq/zhenjiang_target_state_diagnostic_20260930_001')
JOB = '232378'
REGISTRY_SHA = '84c707fd40f37d955417add0a5bd08c7ec8512ec266f82510433b094c11858ad'
MANIFEST_SHA = 'cd05b3755e9fa675e1c6d4995f0016e65d277287a97c28e82f2d42bcb36dcbb9'


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def read(path, limit=500000):
    raw = path.read_bytes()
    if len(raw) > limit:
        raise ValueError('registered receipt exceeded bound')
    return json.loads(raw)


def main():
    submitted = read(ROOT / 'submission/submitted.json')
    attempt = read(ROOT / 'submission/attempt.json')
    scheduler = read(ROOT / 'submission/scheduler_reply.json')
    if (submitted['status'] != 'SUBMITTED_ONCE' or submitted['job_id'] != JOB
            or submitted['planned_tasks'] != 24 or attempt['planned_tasks'] != 24
            or attempt['maximum_simultaneous_gpu_tasks'] != 2
            or scheduler['returncode'] != 0
            or scheduler['stdout'].count('Submitted batch job ' + JOB) != 1):
        raise ValueError('unique submission receipt differs')
    registry_raw = (ROOT / 'registry_frozen.json').read_bytes()
    manifest_raw = (ROOT / 'reports/training_manifest.json').read_bytes()
    if sha(registry_raw) != REGISTRY_SHA or sha(manifest_raw) != MANIFEST_SHA:
        raise ValueError('registered source manifest or run list changed')
    registry, manifest = json.loads(registry_raw), json.loads(manifest_raw)
    issues = []
    for relative, expected in manifest['files'].items():
        path = ROOT / relative
        if (path.is_symlink() or not path.is_file() or path.stat().st_size != expected['bytes']
                or sha(path.read_bytes()) != expected['sha256']):
            issues.append('sealed source changed: ' + relative)
    expected_names = {row['exp_id'] for row in registry['runs']}
    runs = ROOT / 'runs'
    if runs.is_dir():
        unknown = {p.name for p in runs.iterdir() if p.is_dir()} - expected_names
        issues.extend('unregistered run directory: ' + name for name in sorted(unknown))
    rows, completed, failed, records, started = [], 0, 0, 0, 0
    gpu_names = set()
    for index, row in enumerate(registry['runs']):
        path = runs / row['exp_id']
        epochs = sorted(path.glob('epoch_*.json')) if path.is_dir() else []
        attempt_path, complete_path, failure_path = path / 'attempt.json', path / 'complete.json', path / 'failure.json'
        item = {'experiment_id': row['exp_id'], 'array_index': index, 'epoch_records': len(epochs),
                'last_epoch': None, 'last_epoch_modified_unix_seconds': None,
                'complete': complete_path.is_file(), 'failure': failure_path.is_file()}
        if path.is_dir():
            started += 1
        if attempt_path.is_file():
            receipt = read(attempt_path)
            gpu_names.add(receipt['hardware']['gpu_name'])
            if (receipt['experiment_id'] != row['exp_id'] or receipt['array_index'] != index
                    or receipt['registry_sha256'] != REGISTRY_SHA or receipt['manifest_sha256'] != MANIFEST_SHA
                    or receipt['source_input_ledger'] != registry['training_sources']
                    or 'RTX 3090' not in receipt['hardware']['gpu_name']
                    or receipt['hardware']['slurm_array_job_id'] != JOB):
                issues.append('training attempt or hardware identity differs: ' + row['exp_id'])
        numbers = []
        for epoch_path in epochs:
            epoch = read(epoch_path)
            number = int(epoch_path.stem.split('_')[1])
            numbers.append(number)
            if (epoch['epoch'] != number or epoch['experiment_id'] != row['exp_id']
                    or not math.isfinite(epoch['selection_unweighted_error_m'])
                    or (number > 0 and not math.isfinite(epoch['train_weighted_error_m']))
                    or not (ROOT / epoch['checkpoint']['relative_path']).is_file()):
                issues.append('epoch record differs or loss is nonfinite: ' + row['exp_id'])
        if numbers:
            item['last_epoch'] = max(numbers)
            item['last_epoch_modified_unix_seconds'] = max(p.stat().st_mtime for p in epochs)
            if numbers != list(range(len(numbers))) or len(numbers) > 101:
                issues.append('noncontiguous epoch history: ' + row['exp_id'])
        if item['complete']:
            completed += 1
            complete = read(complete_path)
            if (numbers != list(range(101)) or complete['epoch_records'] != 101
                    or complete['experiment_id'] != row['exp_id']
                    or complete['registry_sha256'] != REGISTRY_SHA or complete['manifest_sha256'] != MANIFEST_SHA):
                issues.append('completion receipt differs: ' + row['exp_id'])
        if item['failure']:
            failed += 1
            failure = read(failure_path)
            item['failure_reason'] = {key: failure.get(key) for key in ('phase', 'error')}
        records += len(epochs)
        rows.append(item)
    state = {}
    for key, argv in [('queue', ['squeue', '-r', '-j', JOB, '-h', '-o', '%A|%a|%T|%M|%R|%j']),
                      ('accounting', ['sacct', '-j', JOB, '--starttime', '2026-09-30', '--noheader',
                                      '--parsable2', '--format=JobIDRaw,State,ExitCode,Elapsed,NodeList'])]:
        result = subprocess.run(argv, capture_output=True, text=True, timeout=15, check=False)
        if len(result.stdout.encode()) + len(result.stderr.encode()) > 20000:
            raise ValueError('bounded scheduling response exceeded limit')
        state[key] = {'returncode': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr}
    print(json.dumps({'status': 'BOUNDED_READ_ONLY_STATUS', 'job_id': JOB, 'root': str(ROOT),
                      'query_unix_seconds': time.time(), 'planned_runs': 24, 'started_runs': started,
                      'completed_runs': completed, 'failed_runs': failed, 'epoch_records': records,
                      'expected_epoch_records': 2424, 'source_files_verified': len(manifest['files']),
                      'source_registry_sha256': REGISTRY_SHA, 'source_manifest_sha256': MANIFEST_SHA,
                      'gpu_names': sorted(gpu_names), 'issues': issues, 'runs': rows, 'scheduler': state}, sort_keys=True))


if __name__ == '__main__':
    main()

ZJ_TARGET_STATUS
