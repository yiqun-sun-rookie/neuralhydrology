#!/usr/bin/env bash
set -euo pipefail

phase=/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/full_budget_integrated_release_20260927_attempt1
job_id=228327

printf '=== FIRST-BASIN MODEL READ-ONLY PROGRESS ===\n'
date -u '+UTC=%Y-%m-%dT%H:%M:%SZ'
printf '%s\n' '=== ACCOUNTING ==='
sacct -X -j "$job_id" -P -n --format=JobID,JobName,Partition,ElapsedRaw,State,ExitCode
printf '%s\n' '=== QUEUE ==='
squeue -j "$job_id" -h -o '%i|%j|%T|%R'
/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python -B - "$phase" <<'PY'
import json
from pathlib import Path
import stat
import sys

phase = Path(sys.argv[1])
if not phase.is_dir() or phase.is_symlink():
    raise SystemExit('exclusive phase missing or linked')
basin = phase / 'basin_01047000'
paths = (
    'control/job_gate.json',
    'run/model/started.json',
    'run/stdout.log',
    'run/stderr.log',
    'run/supervisor.json',
    'run/model/summary.json',
    'run/model/manifest.final.sha256.json',
)
for relative in paths:
    path = basin / relative
    try:
        mode = path.lstat().st_mode
    except FileNotFoundError:
        print(f'ABSENT {relative}')
        continue
    if not stat.S_ISREG(mode):
        print(f'NONREGULAR {relative} mode={oct(mode)}')
        continue
    size = path.stat().st_size
    print(f'PRESENT {relative} bytes={size}')
    if relative.endswith('.json'):
        try:
            data = json.loads(path.read_text(encoding='utf-8'))
        except Exception as error:
            print(f'JSON_UNREADABLE {relative} {type(error).__name__}: {error}')
            continue
        keys = ('status', 'basin_id', 'reason', 'success', 'exit_code', 'wall_seconds', 'checkpoint_count', 'training_objective_evaluations', 'validation_objective_evaluations')
        print('DETAIL ' + relative + ' ' + json.dumps({key: data[key] for key in keys if key in data}, sort_keys=True, separators=(',', ':')))
    elif relative.endswith('.log'):
        with path.open('rb') as stream:
            stream.seek(max(0, size - 5000))
            tail = stream.read().decode('utf-8', errors='replace')
        print('TAIL ' + relative + ' ' + repr(tail))
        if relative == 'run/stdout.log':
            with path.open('rb') as stream:
                marker = False
                overlap = b''
                needle = b'FULL_BUDGET_MODEL_STARTED'
                while True:
                    chunk = stream.read(65536)
                    if not chunk:
                        break
                    marker = needle in overlap + chunk
                    if marker:
                        break
                    overlap = chunk[-len(needle):]
            print(f'MODEL_CALCULATION_ENTRY_MARKER={marker}')
model = basin / 'run/model'
if model.is_dir() and not model.is_symlink():
    files = sorted((entry.name, entry.stat().st_size) for entry in model.iterdir() if entry.is_file() and not entry.is_symlink())
    print('MODEL_FILE_LIST ' + json.dumps(files, separators=(',', ':')))
PY
printf '%s\n' 'READ_ONLY_FIRST_BASIN_MODEL_PROGRESS_COMPLETE'
