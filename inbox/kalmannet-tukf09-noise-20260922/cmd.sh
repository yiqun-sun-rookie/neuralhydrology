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

phase = Path('/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/timing_probe_01142500_20260929_attempt2')
job = '231059'
if phase.is_symlink() or not phase.is_dir():
    raise RuntimeError('isolated diagnostic root missing or linked')
print('TIMING_DIAGNOSTIC_TERMINAL_CORE_BEGIN job=' + job)
for label, command in (
    ('ACCOUNTING', ['sacct', '-X', '-j', job, '-P', '-n', '--format=JobID,JobName,Partition,AllocCPUS,ReqCPUS,AllocTRES,ReqTRES,ElapsedRaw,State,ExitCode,Start,End,Timelimit']),
    ('QUEUE', ['squeue', '-j', job, '-h', '-o', '%i|%j|%T|%R']),
):
    result = subprocess.run(command, text=True, capture_output=True, timeout=30)
    print(label + ' ' + json.dumps({'returncode': result.returncode,
                                    'stdout': result.stdout[-3000:],
                                    'stderr': result.stderr[-1000:]}, sort_keys=True))
fixed = [
    'payload_manifest.json',
    'basin_01142500/control/deployment.json',
    'basin_01142500/control/submission_attempt.json',
    'basin_01142500/control/submission.json',
    'basin_01142500/control/job_gate.json',
    'basin_01142500/control/diagnostic_gate.json',
    'basin_01142500/run/supervisor.json',
    'basin_01142500/run/stdout.log',
    'basin_01142500/run/stderr.log',
    'basin_01142500/run/model/started.json',
    'basin_01142500/run/model/diagnostic_complete.json',
    'basin_01142500/run/model/diagnostic_manifest.sha256.json',
    'logs/job-231059.out',
    'logs/job-231059.err',
]
progress = [f'basin_01142500/run/model/call_{i:03d}.json' for i in range(1, 129)]
progress += [f'basin_01142500/run/model/update_{i:03d}.json' for i in range(1, 65)]
paths = fixed + progress
print('EXPECTED_FILES=' + str(len(paths)))
total = 0
for relative in paths:
    path = phase / relative
    if not path.exists() and not path.is_symlink():
        print('ABSENT ' + relative)
        continue
    if not stat.S_ISREG(path.lstat().st_mode):
        raise RuntimeError('linked or nonregular terminal evidence: ' + relative)
    data = path.read_bytes()
    total += len(data)
    if len(data) > 150000 or total > 500000:
        raise RuntimeError('terminal core evidence exceeds retrieval bound')
    print('EVIDENCE ' + json.dumps({
        'path': relative,
        'size_bytes': len(data),
        'sha256': hashlib.sha256(data).hexdigest(),
        'base64': base64.b64encode(data).decode('ascii'),
    }, sort_keys=True, separators=(',', ':')))
for label, relative in (
    ('MODEL_ENTRIES', 'basin_01142500/run/model'),
    ('CONTROL_ENTRIES', 'basin_01142500/control'),
    ('RUN_ENTRIES', 'basin_01142500/run'),
):
    directory = phase / relative
    if directory.is_symlink() or not directory.is_dir():
        raise RuntimeError('linked or missing terminal directory: ' + relative)
    print(label + ' ' + json.dumps(sorted(path.name for path in directory.iterdir())))
print('TOTAL_BYTES=' + str(total))
print('TIMING_DIAGNOSTIC_TERMINAL_CORE_END')
PY
