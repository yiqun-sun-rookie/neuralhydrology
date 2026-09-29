#!/usr/bin/env bash
set -euo pipefail
export PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1

/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python -B - <<'PY'
import hashlib
import json
from pathlib import Path
import stat
import subprocess

phase = Path('/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/timing_probe_01142500_20260929_attempt2')
job = '231059'
if phase.is_symlink() or not phase.is_dir():
    raise SystemExit('isolated diagnostic root missing or linked')
print('TIMING_DIAGNOSTIC_READONLY_STATUS_BEGIN job=' + job)
for label, command in (
    ('ACCOUNTING', ['sacct', '-X', '-j', job, '-P', '-n', '--format=JobID,JobName,Partition,AllocCPUS,ReqCPUS,AllocTRES,ReqTRES,ElapsedRaw,State,ExitCode,Start,End,Timelimit']),
    ('QUEUE', ['squeue', '-j', job, '-h', '-o', '%i|%j|%T|%R']),
):
    result = subprocess.run(command, text=True, capture_output=True, timeout=30)
    print(label + ' ' + json.dumps({'returncode': result.returncode, 'stdout': result.stdout[-3000:],
                                    'stderr': result.stderr[-1000:]}, sort_keys=True))
paths = (
    'basin_01142500/control/deployment.json',
    'basin_01142500/control/submission_attempt.json',
    'basin_01142500/control/submission.json',
    'basin_01142500/control/job_gate.json',
    'basin_01142500/control/diagnostic_gate.json',
    'basin_01142500/run/supervisor.json',
    'basin_01142500/run/model/started.json',
    'basin_01142500/run/model/diagnostic_complete.json',
    'basin_01142500/run/model/diagnostic_manifest.sha256.json',
    'logs/job-231059.out',
    'logs/job-231059.err',
)
for relative in paths:
    path = phase / relative
    if not path.exists() and not path.is_symlink():
        print('ABSENT ' + relative)
        continue
    if not stat.S_ISREG(path.lstat().st_mode):
        raise RuntimeError('linked or nonregular evidence: ' + relative)
    raw = path.read_bytes()
    print('EVIDENCE ' + json.dumps({'path': relative, 'size_bytes': len(raw),
                                   'sha256': hashlib.sha256(raw).hexdigest(),
                                   'tail_utf8': raw[-3500:].decode('utf-8', errors='replace')}, sort_keys=True))
model = phase / 'basin_01142500/run/model'
if model.is_dir() and not model.is_symlink():
    for label, pattern in (('CALLS', 'call_*.json'), ('UPDATES', 'update_*.json')):
        members = list(model.glob(pattern))
        if any(item.is_symlink() or not item.is_file() for item in members):
            raise RuntimeError('linked or nonregular progress file')
        print(label + '_COUNT=' + str(len(members)))
print('TIMING_DIAGNOSTIC_READONLY_STATUS_END')
PY
