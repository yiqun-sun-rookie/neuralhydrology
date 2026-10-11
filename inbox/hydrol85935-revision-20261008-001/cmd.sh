#!/usr/bin/env bash
set -eo pipefail
ROOT=/data1/home/sunyiq/hydrol85935_revision_20261008_001
test "$(readlink -f "$ROOT")" = "$ROOT"
test "$(cat "$ROOT/OWNER")" = hydrol85935_revision_20261008_001
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - <<'PY'
import datetime
import json
from pathlib import Path
import subprocess

root = Path('/data1/home/sunyiq/hydrol85935_revision_20261008_001')
execution = root / 'execution/v004'

def output(label, value):
    print(label + ' ' + json.dumps(value, ensure_ascii=False), flush=True)

def safe(path):
    path.resolve().relative_to(root)
    return path

def metadata(path):
    path = safe(path)
    if not path.exists():
        return {'path': str(path.relative_to(root)), 'exists': False}
    s = path.stat()
    return {'path': str(path.relative_to(root)), 'exists': True,
            'bytes': s.st_size, 'mtime_ns': s.st_mtime_ns}

def small_file(relative):
    p = root / relative
    result = metadata(p)
    if result['exists']:
        if result['bytes'] > 65536:
            raise ValueError('Unexpectedly large status file: ' + relative)
        result['text'] = p.read_text()
    output('FILE', result)

def tail(path, limit=5000):
    info = metadata(path)
    if info['exists']:
        with path.open('rb') as stream:
            stream.seek(max(0, info['bytes'] - limit))
            info['tail'] = stream.read().decode(errors='replace')
    output('LOG', info)

output('OBSERVATION', {'time': datetime.datetime.now().astimezone().isoformat(),
                       'scope': 'read-only scheduler, task status, logs and output metadata; no science execution'})
for relative in [
    'control/continuation_v004/status.json', 'control/full_v004/jobs.json',
    'control/continuation_v004/coordinator_pid',
    'runtime_torch271cu118/DOWNLOAD_COMPLETE.json',
    'runtime_torch271cu118/INSTALL_COMPLETE.json',
    'control/resource_pilot_v004.json',
    'execution/v004/control/train_failure.json',
    'execution/v004/control/main_failure.json',
    'execution/v004/control/validation.json',
]:
    small_file(relative)
jobs = json.loads((root / 'control/full_v004/jobs.json').read_text())
if jobs != {'train': 240076, 'attacks': 240077, 'report': 240078}:
    raise ValueError('Unrecognized job registry; stop rather than infer ownership')
for label, command in [
    ('SQUEUE', ['squeue', '-j', ','.join(str(j) for j in jobs.values()), '-o',
                '%.24i %.10T %.12M %.6C %.16b %.30R']),
    ('SACCT', ['sacct', '-X', '-j', '240074,240075,' + ','.join(str(j) for j in jobs.values()),
               '-n', '-P', '-o', 'JobID,State,ExitCode,Elapsed,Start,End,NodeList']),
    ('TRAIN_DETAIL', ['scontrol', '-o', 'show', 'job', str(jobs['train'])]),
]:
    result = subprocess.run(command, capture_output=True, text=True, timeout=45)
    output(label, {'returncode': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr})
pid = (root / 'control/continuation_v004/coordinator_pid').read_text().strip()
if not pid.isdigit():
    raise ValueError('Invalid coordinator PID')
result = subprocess.run(['ps', '-p', pid, '-o', 'pid,etimes,args'], capture_output=True, text=True, timeout=15)
output('COORDINATOR', {'returncode': result.returncode, 'stdout': result.stdout,
                       'absence_expected_after_formal_handoff': True})
for seed in (100, 200, 300):
    directory = execution / 'training' / ('s' + str(seed))
    small_file(str((directory / 'complete.json').relative_to(root)))
    files = sorted(directory.glob('runs/*/model_epoch*.pt'))
    output('TRAIN_CHECKPOINTS', {'seed': seed, 'count': len(files),
                                'latest': [metadata(p) for p in files[-3:]]})
    for p in sorted(directory.glob('runs/*/*.log'))[-3:]:
        tail(p)
for pattern in ['train-240076_*.out', 'train-240076_*.err',
                'attacks-240077_*.out', 'attacks-240077_*.err',
                'report-240078*.out', 'report-240078*.err']:
    paths = sorted((root / 'logs').glob(pattern), key=lambda p: p.stat().st_mtime_ns)
    output('LOG_INVENTORY', {'pattern': pattern, 'count': len(paths)})
    for p in paths[-4:]:
        tail(p)
for name, pattern in [('attack_complete_markers', 'records/attacks/*/*/complete.json'),
                      ('clean_complete_markers', 'records/clean/*/*/complete.json'),
                      ('chunk_summaries', 'control/chunk_*.json')]:
    paths = list(execution.glob(pattern))
    output('OUTPUT_METADATA', {'kind': name, 'count': len(paths),
                               'latest': [metadata(p) for p in sorted(paths, key=lambda p: p.stat().st_mtime_ns)[-3:]],
                               'complete_coverage_audit': False})
tail(execution / 'records/ledger.jsonl', 4000)
PY
