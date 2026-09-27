#!/usr/bin/env bash
set -euo pipefail

phase=/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/full_budget_integrated_release_20260927_attempt1
job_id=228327

printf '=== FIRST-BASIN JOB READ-ONLY STATUS ===\n'
date -u '+UTC=%Y-%m-%dT%H:%M:%SZ'
printf '%s\n' '=== ACCOUNTING ==='
sacct -X -j "$job_id" -P -n --format=JobID,JobName,Partition,ElapsedRaw,State,ExitCode
printf '%s\n' '=== QUEUE ==='
squeue -j "$job_id" -h -o '%i|%j|%T|%R'
printf '%s\n' '=== EXACT FIRST-BASIN FILES ==='
/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python -B - "$phase" "$job_id" <<'PY'
import json
import os
from pathlib import Path
import stat
import sys

phase = Path(sys.argv[1])
job_id = sys.argv[2]
if not phase.is_dir() or phase.is_symlink():
    raise SystemExit('exclusive phase missing or linked')

paths = (
    'basin_01047000/control/submission_attempt.json',
    'basin_01047000/control/submission.json',
    'basin_01047000/control/original_tests.xml',
    'basin_01047000/control/output_guard_regression.xml',
    'basin_01047000/control/new_gate_tests.xml',
    'basin_01047000/control/tensor_tests/tensor_tests.xml',
    'basin_01047000/control/job_gate.json',
    'basin_01047000/run/model/started.json',
    'basin_01047000/run/model/summary.json',
    'basin_01047000/run/model/manifest.final.sha256.json',
    'basin_01047000/run/supervisor.json',
    f'logs/job-{job_id}.out',
    f'logs/job-{job_id}.err',
)
for relative in paths:
    path = phase / relative
    try:
        mode = path.lstat().st_mode
    except FileNotFoundError:
        print(f'ABSENT {relative}')
        continue
    if not stat.S_ISREG(mode):
        print(f'NONREGULAR {relative} mode={oct(mode)}')
        continue
    print(f'PRESENT {relative} bytes={path.stat().st_size}')
    if relative.endswith(('submission.json', 'job_gate.json', 'started.json', 'summary.json', 'supervisor.json')):
        try:
            data = json.loads(path.read_text(encoding='utf-8'))
        except Exception as error:
            print(f'JSON_UNREADABLE {relative} {type(error).__name__}: {error}')
            continue
        selected = {key: data.get(key) for key in ('status', 'basin_id', 'job_id', 'stage_id', 'success', 'returncode', 'failure_reason', 'elapsed_seconds') if key in data}
        print('DETAIL ' + relative + ' ' + json.dumps(selected, sort_keys=True, separators=(',', ':')))
    if relative.endswith(('.out', '.err')):
        with path.open('rb') as stream:
            stream.seek(max(0, path.stat().st_size - 3000))
            tail = stream.read().decode('utf-8', errors='replace')
        print('TAIL ' + relative + ' ' + repr(tail))
PY
printf '%s\n' 'READ_ONLY_FIRST_BASIN_JOB_STATUS_COMPLETE'
