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

phase = Path('/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/full_budget_01142500_20260928_attempt1')
job = '229133'
paths = (
    'control/deployed.json',
    'basin_01142500/control/submission_attempt.json',
    'basin_01142500/control/submission.json',
    'basin_01142500/control/job_gate.json',
    'basin_01142500/control/original_tests.xml',
    'basin_01142500/control/output_guard_regression.xml',
    'basin_01142500/control/new_gate_tests.xml',
    'basin_01142500/control/tensor_tests/tensor_tests.xml',
    'basin_01142500/control/tensor_tests/supervisor.json',
    'basin_01142500/control/tensor_tests/stdout.log',
    'basin_01142500/control/tensor_tests/stderr.log',
    'basin_01142500/run/supervisor.json',
    'basin_01142500/run/stdout.log',
    'basin_01142500/run/stderr.log',
    'basin_01142500/run/model/started.json',
    'basin_01142500/run/model/summary.json',
    'basin_01142500/run/model/history.npz',
    'basin_01142500/run/model/manifest.final.sha256.json',
    'logs/job-229133.out',
    'logs/job-229133.err',
)
print('ONE20_TERMINAL_EVIDENCE_BEGIN job=' + job + ' count=' + str(len(paths)))
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
    if len(data) > 500000 or total > 1000000:
        raise RuntimeError('terminal evidence exceeds retrieval bound')
    print('EVIDENCE ' + json.dumps({
        'path': relative,
        'size_bytes': len(data),
        'sha256': hashlib.sha256(data).hexdigest(),
        'base64': base64.b64encode(data).decode('ascii'),
    }, sort_keys=True, separators=(',', ':')))
for label, command in (
    ('ACCOUNTING', ['sacct', '-X', '-j', job, '-P', '-n', '--format=JobID,JobName,Partition,AllocCPUS,ReqCPUS,AllocTRES,ReqTRES,ElapsedRaw,State,ExitCode,Start,End,Timelimit']),
    ('QUEUE', ['squeue', '-j', job, '-h', '-o', '%i|%j|%T|%R']),
):
    result = subprocess.run(command, text=True, capture_output=True, timeout=30)
    print(label + ' ' + json.dumps({'returncode': result.returncode,
                                    'stdout': result.stdout[-3000:],
                                    'stderr': result.stderr[-1000:]}, sort_keys=True))
print('ONE20_TERMINAL_EVIDENCE_END')
PY
