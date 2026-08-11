#!/bin/bash
# ID29 seq=197: read-only evaluation-array dependency-release planning estimate.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da

echo "=== SNAPSHOT TIME ==="
date --iso-8601=seconds

echo "=== EVALUATION ARRAY TASK RECORDS ==="
sacct -n -P -j 202222 --format=JobID,State,ExitCode,ElapsedRaw,Elapsed,Start,End

echo "=== PLANNING ESTIMATE ==="
python - <<'PY'
from datetime import datetime, timedelta
import json
import math
from pathlib import Path
import re
import statistics
import subprocess

records = subprocess.run(
    [
        'sacct', '-n', '-P', '-j', '202222',
        '--format=JobID,State,ExitCode,ElapsedRaw,Elapsed,Start,End',
    ],
    check=True, capture_output=True, text=True,
).stdout.splitlines()
task_pattern = re.compile(r'^202222_(\d+)$')
tasks = {}
for line in records:
    fields = line.split('|')
    if len(fields) < 7:
        continue
    match = task_pattern.fullmatch(fields[0])
    if not match:
        continue
    task = int(match.group(1))
    tasks[task] = {
        'state': fields[1],
        'exit_code': fields[2],
        'elapsed_seconds': int(fields[3] or 0),
        'elapsed': fields[4],
        'start': fields[5],
        'end': fields[6],
    }

completed = sorted(task for task, row in tasks.items() if row['state'] == 'COMPLETED')
running = sorted(task for task, row in tasks.items() if row['state'] == 'RUNNING')
pending = sorted(set(range(30)) - set(completed) - set(running))
failed = sorted(
    task for task, row in tasks.items()
    if row['state'] in {
        'FAILED', 'TIMEOUT', 'OUT_OF_MEMORY', 'NODE_FAIL', 'PREEMPTED',
        'BOOT_FAIL', 'DEADLINE',
    }
)
long_durations = sorted(
    tasks[task]['elapsed_seconds'] for task in completed
    if tasks[task]['elapsed_seconds'] >= 3600
)
if not long_durations:
    raise ValueError('No completed long evaluation tasks are available for planning')

ansi = re.compile(r'\x1b\[[0-9;]*[A-Za-z]')
progress_pattern = re.compile(r'(?<!Epoch\s)(\d+)%\|.*?\|\s*(\d+)/(\d+)')
running_estimates = []
for task in running:
    job = f'202222_{task}'
    record = subprocess.run(
        ['scontrol', 'show', 'job', '-o', job], check=True, capture_output=True, text=True,
    ).stdout.strip()
    fields = dict(token.split('=', 1) for token in record.split() if '=' in token)
    stdout = Path(fields['StdOut'])
    payload = {'task': task, 'job': job, 'runtime': fields['RunTime']}
    if stdout.is_file():
        size = stdout.stat().st_size
        with stdout.open('rb') as handle:
            handle.seek(max(0, size - 4 * 1024 * 1024))
            tail = ansi.sub('', handle.read().decode('utf-8', errors='replace')).replace('\r', '\n')
        matches = list(progress_pattern.finditer(tail))
        if matches:
            percent, step, total = map(int, matches[-1].groups())
            fraction = step / total
            elapsed = tasks[task]['elapsed_seconds']
            total_seconds = elapsed / fraction
            remaining_seconds = max(0.0, total_seconds - elapsed)
            payload.update({
                'reported_percent': percent,
                'completed_basins': step,
                'total_basins': total,
                'projected_total_hours': round(total_seconds / 3600, 2),
                'projected_remaining_hours': round(remaining_seconds / 3600, 2),
            })
    running_estimates.append(payload)

if not running_estimates or any('projected_remaining_hours' not in row for row in running_estimates):
    raise ValueError('Every running task must have a progress-based projection')

current_wave_remaining = max(row['projected_remaining_hours'] for row in running_estimates)
future_waves = math.ceil(len(pending) / 2)
duration_hours = {
    'lower': min(long_durations) / 3600,
    'median': statistics.median(long_durations) / 3600,
    'upper': max(long_durations) / 3600,
}
now = datetime.now().astimezone()
finish = {
    key: now + timedelta(hours=current_wave_remaining + future_waves * value)
    for key, value in duration_hours.items()
}
print(json.dumps({
    'schema': 'nearing2022-evaluation-array-planning-estimate-v1',
    'array_job_id': '202222',
    'array_tasks_total': 30,
    'array_concurrency': 2,
    'completed_tasks': completed,
    'running_tasks': running,
    'pending_tasks': pending,
    'failed_tasks': failed,
    'completed_long_task_count': len(long_durations),
    'completed_long_duration_hours': [round(value / 3600, 3) for value in long_durations],
    'completed_long_duration_summary_hours': {
        key: round(value, 3) for key, value in duration_hours.items()
    },
    'running_task_estimates': running_estimates,
    'future_waves_after_current': future_waves,
    'projected_dependency_release': {
        key: value.isoformat(timespec='seconds') for key, value in finish.items()
    },
    'replacement_job_202510_can_start_only_after_parent_terminal': True,
    'planning_only': True,
    'registered_matrix_modified': False,
}, indent=2, sort_keys=True))
PY

echo "=== REPLACEMENT AND FROZEN STATES ==="
sacct -n -X -P -j 202510,202511 --format=JobIDRaw,JobName,State,ExitCode,Elapsed,Reason
squeue -h -j 202510,202511 -o '%i|%j|%T|%M|%R|%E' | sort
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = '202293|PENDING|JobHeldUser|N22-manifest'
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"
echo "pair_training_submitted=false"
echo "registered_matrix_modified=false"
