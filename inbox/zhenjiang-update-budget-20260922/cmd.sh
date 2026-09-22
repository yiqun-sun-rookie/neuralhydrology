#!/bin/bash
set -euo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -I -B - <<'ZHENJIANG_BUDGET_STATUS'
import json
from pathlib import Path
import subprocess

root = Path('/data1/home/sunyiq/zhenjiang_update_budget_20260922_001')
run = root / 'run'
job = '227320'

def command(argv):
    try:
        reply = subprocess.run(argv, capture_output=True, text=True,
                               encoding='utf-8', errors='replace',
                               timeout=15, check=False)
        return {'returncode': reply.returncode,
                'stdout': reply.stdout[:3000], 'stderr': reply.stderr[:500]}
    except Exception as error:
        return {'error_type': type(error).__name__, 'message': str(error)[:300]}

def small_record(name):
    path = run / name
    if not path.is_file() or path.is_symlink() or path.stat().st_size > 1000000:
        return None
    try:
        value = json.loads(path.read_bytes())
        if name == 'failure.json':
            return {k: value.get(k) for k in ('status', 'error_type', 'message', 'statuses')}
        if name == 'complete.json':
            return {k: value.get(k) for k in ('status', 'job_id', 'elapsed_seconds')}
        return {k: value.get(k) for k in ('status', 'job_id')}
    except Exception as error:
        return {'error_type': type(error).__name__}

groups = {}
if run.is_dir() and not run.is_symlink():
    for seed in (17, 29, 43):
        for stage in ('rolling_encoder', 'differentiable_filter'):
            directory = run / ('seed_' + str(seed)) / stage
            names = list(directory.glob('epoch_*.json')) if directory.is_dir() else []
            groups[str(seed) + '/' + stage] = {
                'epoch_json_count': sum(name.stem[6:].isdigit() for name in names),
                'identity_20_present': (directory / 'epoch_20_identity.json').is_file(),
                'selection_present': (directory / 'selection.json').is_file()}

print(json.dumps({'job_id': job,
                  'squeue': command(['squeue', '-j', job, '-h', '-o', '%T|%M|%R']),
                  'sacct': command(['sacct', '-P', '-n', '-j', job,
                                    '--format=JobID,State,Elapsed,ExitCode']),
                  'run_exists': run.is_dir(),
                  'attempt': small_record('attempt.json'),
                  'complete': small_record('complete.json'),
                  'failure': small_record('failure.json'),
                  'groups': groups}, sort_keys=True))
ZHENJIANG_BUDGET_STATUS
