#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
"""Inspect only the registered diagnostic job and its scheduling constraints."""
import datetime
import json
from pathlib import Path
import subprocess

root = Path('/data1/home/sunyiq/zhenjiang_gradient_diagnostic_20261011_001')
jobs = json.loads((root / 'records/scheduler_jobs.json').read_text())
spec = json.loads((root / 'diagnostic_spec.json').read_text())
job = str(jobs['gradient_diagnostic'])
assert job.isdigit()
commands = [
    ['scontrol', 'show', 'job', '-o', job],
    ['squeue', '-h', '-j', job, '-o', '%i|%j|%T|%R|%N|%M|%V|%S'],
    ['sacct', '-n', '-X', '-j', job, '--format=JobID,JobName,State,ExitCode,Elapsed,NodeList,Reason', '-P'],
    ['sprio', '-j', job, '-l'],
    ['sinfo', '-h', '-p', 'hgpu2p', '-N', '-o', '%N|%T|%G|%C|%m'],
]
queries = []
for command in commands:
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=30)
        queries.append({'command': command, 'returncode': result.returncode,
                        'stdout': result.stdout, 'stderr': result.stderr})
    except (OSError, subprocess.TimeoutExpired) as exc:
        queries.append({'command': command, 'error': str(exc)})
print(json.dumps({'schema': 'read_only_registered_diagnostic_queue_detail_v1',
                  'checked_at_beijing': datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
                  'diagnostic_root': str(root), 'job_id': job, 'expected_job_name': spec['job_name'],
                  'queries': queries, 'scheduler_mutated': False, 'training_data_read': False,
                  'evaluation_values_read': False}, sort_keys=True))
PY
