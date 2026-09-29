#!/usr/bin/env bash
set -euo pipefail
export PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1

/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python -B - <<'PY'
import base64
import hashlib
import json
from pathlib import Path
import stat
import subprocess

phase = Path('/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/full_budget_01142500_20260929_attempt2')
job = '231213'
if phase.is_symlink() or not phase.is_dir():
    raise RuntimeError('isolated full-budget root missing or linked')
print('FULL_BUDGET_ATTEMPT2_TERMINAL_EVIDENCE_BEGIN job=' + job)
records = {}
for label, command in (
    ('ACCOUNTING', ['sacct', '-X', '-j', job, '-P', '-n', '--format=JobID,JobName,Partition,AllocCPUS,ReqCPUS,AllocTRES,ReqTRES,ElapsedRaw,State,ExitCode,Start,End,Timelimit']),
    ('QUEUE', ['squeue', '-j', job, '-h', '-o', '%i|%j|%T|%R']),
):
    result = subprocess.run(command, text=True, capture_output=True, timeout=30)
    records[label] = {'returncode': result.returncode, 'stdout': result.stdout[-3000:], 'stderr': result.stderr[-1000:]}
    print(label + ' ' + json.dumps(records[label], sort_keys=True))
if records['ACCOUNTING']['returncode'] != 0 or '|COMPLETED|0:0|' not in records['ACCOUNTING']['stdout']:
    raise RuntimeError('terminal scheduler accounting is not completed with zero exit code')
entries = []
total = 0
for path in sorted(phase.rglob('*')):
    relative = path.relative_to(phase).as_posix()
    if path.is_symlink():
        raise RuntimeError('linked terminal entry: ' + relative)
    mode = path.lstat().st_mode
    if stat.S_ISDIR(mode):
        continue
    if not stat.S_ISREG(mode):
        raise RuntimeError('nonregular terminal entry: ' + relative)
    data = path.read_bytes()
    total += len(data)
    if len(data) > 1000000 or total > 2000000:
        raise RuntimeError('terminal evidence exceeds retrieval bound')
    entries.append((relative, data))
print('EVIDENCE_FILE_COUNT=' + str(len(entries)))
for relative, data in entries:
    print('EVIDENCE ' + json.dumps({
        'path': relative,
        'size_bytes': len(data),
        'sha256': hashlib.sha256(data).hexdigest(),
        'base64': base64.b64encode(data).decode('ascii'),
    }, sort_keys=True, separators=(',', ':')))
print('TOTAL_BYTES=' + str(total))
print('FULL_BUDGET_ATTEMPT2_TERMINAL_EVIDENCE_END')
PY