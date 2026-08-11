#!/bin/bash
# ID29 seq=238: inlined frozen read-only matrix progress, walltime, dependency-release, and boundary audit.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
IDEA="$ROOT/src/29_nearing2022_da_ar"
REGISTRY="$IDEA/registry"
AGGREGATION="$ROOT/closure_20260810/aggregation"
DIAGNOSTICS="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics"
MAIN_JOBS=202214,202215,202216,202222,202226,202227,202228,202229,202230,202238,202293,202294,202315

echo "=== SNAPSHOT TIME ==="
date --iso-8601=seconds

source ~/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
cd "$ROOT"
export PYTHONPATH="$ROOT${PYTHONPATH:+:$PYTHONPATH}"

echo "=== REGISTERED COMPLETE-ROLE COUNTS ==="
python - "$ROOT" "$IDEA" "$REGISTRY" "$AGGREGATION" <<'PY'
from collections import Counter
import json
from pathlib import Path
import sys

import pandas as pd

root = Path(sys.argv[1]).resolve()
idea = Path(sys.argv[2]).resolve()
registry = Path(sys.argv[3]).resolve()
aggregation = Path(sys.argv[4]).resolve()
sys.path.insert(0, str(idea / 'scripts'))

from verify_registered_closure import audit_registered_closure

training = pd.read_csv(registry / 'experiment_registry.csv', keep_default_na=False, dtype=str)
evaluations = pd.read_csv(registry / 'evaluation_registry.csv', keep_default_na=False, dtype=str)
hyperparameters = pd.read_csv(
    registry / 'assimilation_hyperparameter_registry.csv', keep_default_na=False, dtype=str,
)
closure = audit_registered_closure(
    root,
    registry / 'experiment_registry.csv',
    registry / 'evaluation_registry.csv',
    registry / 'assimilation_hyperparameter_registry.csv',
    aggregation / 'evaluations',
    aggregation / 'hyperparameters',
)
missing = {
    coordinate_type: {
        row['coordinate_id'] for row in closure['missing']
        if row['coordinate_type'] == coordinate_type
    }
    for coordinate_type in ('training', 'evaluation', 'hyperparameter')
}


def family_counts(frame, identifier, coordinate_type):
    return dict(sorted(Counter(
        row['family'] for _, row in frame.iterrows()
        if row[identifier] not in missing[coordinate_type]
    ).items()))


print(json.dumps({
    'training_complete': len(training) - len(missing['training']),
    'training_total': len(training),
    'training_by_family': family_counts(training, 'exp_id', 'training'),
    'evaluation_complete': len(evaluations) - len(missing['evaluation']),
    'evaluation_total': len(evaluations),
    'evaluation_by_family': family_counts(evaluations, 'eval_id', 'evaluation'),
    'hyperparameter_complete': len(hyperparameters) - len(missing['hyperparameter']),
    'hyperparameter_total': len(hyperparameters),
    'hyperparameter_by_family': family_counts(hyperparameters, 'eval_id', 'hyperparameter'),
    'missing_roles_total': len(closure['missing']),
    'registered_matrix_complete': closure['complete'],
}, sort_keys=True))
PY

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

echo "=== LIVE RUNNING PROGRESS AND WALLTIME PROJECTION ==="
python - "$MAIN_JOBS" <<'PY'
import json
from pathlib import Path
import re
import subprocess
import sys

parents = sys.argv[1]
running = subprocess.run(
    ['squeue', '-h', '-j', parents, '-t', 'RUNNING', '-o', '%i'],
    check=True, capture_output=True, text=True,
).stdout.split()
ansi = re.compile(r'\x1b\[[0-9;]*[A-Za-z]')
epoch_pattern = re.compile(r'# Epoch\s+(\d+):\s*(\d+)%\|.*?\|\s*(\d+)/(\d+)')
generic_pattern = re.compile(r'(?<!Epoch\s)(\d+)%\|.*?\|\s*(\d+)/(\d+)')


def seconds(value):
    days = 0
    if '-' in value:
        day_text, value = value.split('-', 1)
        days = int(day_text)
    fields = [int(item) for item in value.split(':')]
    if len(fields) == 3:
        hours, minutes, secs = fields
    else:
        hours, minutes, secs = 0, fields[0], fields[1]
    return days * 86400 + hours * 3600 + minutes * 60 + secs


risk_jobs = []
for job in sorted(running):
    record = subprocess.run(
        ['scontrol', 'show', 'job', '-o', job], check=True, capture_output=True, text=True,
    ).stdout.strip()
    fields = dict(token.split('=', 1) for token in record.split() if '=' in token)
    stdout = Path(fields['StdOut'])
    payload = {
        'job': job,
        'name': fields['JobName'],
        'runtime': fields['RunTime'],
        'time_limit': fields['TimeLimit'],
        'stdout_exists': stdout.is_file(),
    }
    if stdout.is_file():
        size = stdout.stat().st_size
        with stdout.open('rb') as handle:
            handle.seek(max(0, size - 4 * 1024 * 1024))
            tail = ansi.sub('', handle.read().decode('utf-8', errors='replace')).replace('\r', '\n')
        epochs = list(epoch_pattern.finditer(tail))
        generic = list(generic_pattern.finditer(tail))
        payload['stdout_bytes'] = size
        if epochs:
            epoch, _, step, total = map(int, epochs[-1].groups())
            fraction = ((epoch - 1) + step / total) / 30
            projected = seconds(fields['RunTime']) / fraction if fraction > 0 else None
            limit = seconds(fields['TimeLimit'])
            risk = projected > limit
            payload.update({
                'epoch': epoch,
                'epoch_step': step,
                'epoch_total_steps': total,
                'thirty_epoch_fraction': round(fraction, 6),
                'projected_total_hours': round(projected / 3600, 2),
                'projected_slack_hours': round((limit - projected) / 3600, 2),
                'time_limit_risk': risk,
            })
            if risk:
                risk_jobs.append(job)
        elif generic:
            percent, step, total = map(int, generic[-1].groups())
            payload.update({'percent': percent, 'step': step, 'total': total})
    print(json.dumps(payload, sort_keys=True))
print(json.dumps({'time_limit_risk_jobs': sorted(risk_jobs), 'running_jobs': len(running)}, sort_keys=True))
PY

echo "=== MAIN JOB STATES AND FAILURE GATE ==="
squeue -h -j "$MAIN_JOBS" -o '%i|%T|%M|%l|%R|%j' | sort
sacct -n -X -P -j "$MAIN_JOBS" --format=JobIDRaw,JobName,State,ExitCode,Elapsed,Start,End,NodeList
MAIN_FAILURES=$(sacct -n -X -P -j "$MAIN_JOBS" --format=JobIDRaw,JobName,State,ExitCode | \
  awk -F'|' '$3 ~ /^(FAILED|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL|PREEMPTED|BOOT_FAIL|DEADLINE)/')
printf '%s\n' "$MAIN_FAILURES"
test -z "$MAIN_FAILURES"

echo "=== REPLACEMENT AND FROZEN STATES ==="
sacct -n -X -P -j 202510,202511 --format=JobIDRaw,JobName,State,ExitCode,Elapsed,Reason
squeue -h -j 202510,202511 -o '%i|%j|%T|%M|%R|%E' | sort
find "$DIAGNOSTICS" -maxdepth 1 -mindepth 1 \
  \( -name 'author_v13_training_data_port_all531_v2*' \
  -o -name 'author_v13_warmup_isolation_all531_v2*' \
  -o -name 'warmup_target_replacement_verification_v1*' \) -printf '%f|%y\n' | sort

PAIR_PRESENT=0
for relative in \
  src/29_nearing2022_da_ar/scripts/prepare_warmup_target_pair.py \
  src/29_nearing2022_da_ar/scripts/analyze_warmup_target_pair.py \
  src/29_nearing2022_da_ar/hpc/run_warmup_target_pair.slurm \
  src/29_nearing2022_da_ar/hpc/analyze_warmup_target_pair.slurm \
  test/test_nearing2022_warmup_pair.py; do
  if test -e "$ROOT/$relative"; then PAIR_PRESENT=$((PAIR_PRESENT + 1)); fi
done
echo "paired_training_payload_present=$PAIR_PRESENT"
test "$PAIR_PRESENT" -eq 0
PAIR_QUEUE=$(squeue -h -n N22-repl-verify,N22-warm-pair,N22-warm-analysis -o '%i|%j|%T|%M|%R')
printf '%s\n' "$PAIR_QUEUE"
test -z "$PAIR_QUEUE"
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = '202293|PENDING|JobHeldUser|N22-manifest'
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"
echo "verification_job_submitted=false"
echo "pair_training_submitted=false"
echo "registered_matrix_modified=false"
