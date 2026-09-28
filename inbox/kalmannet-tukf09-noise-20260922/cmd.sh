#!/usr/bin/env bash
set -euo pipefail
export PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1

/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python -B - <<'PY'
import hashlib
import json
from pathlib import Path
import re
import stat
import subprocess

phase = Path('/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/full_budget_01142500_20260928_attempt1')
print('ONE20_STATUS_QUERY_BEGIN basin=01142500')
if not phase.exists():
    print('PHASE_ABSENT')
    print('ONE20_STATUS_QUERY_END')
    raise SystemExit(0)
if not stat.S_ISDIR(phase.lstat().st_mode):
    raise RuntimeError('new phase is not an unlinked directory')
basin = phase / 'basin_01142500'
for relative in ('control/deployed.json', 'basin_01142500/control/submission_attempt.json',
                 'basin_01142500/control/submission.json', 'basin_01142500/control/job_gate.json',
                 'basin_01142500/run/model/started.json', 'basin_01142500/run/model/summary.json',
                 'basin_01142500/run/model/manifest.final.sha256.json', 'basin_01142500/run/supervisor.json'):
    path = phase / relative
    if path.exists() or path.is_symlink():
        if not stat.S_ISREG(path.lstat().st_mode):
            raise RuntimeError('linked or nonregular status member: ' + relative)
        data = path.read_bytes()
        print('FILE ' + json.dumps({'path': relative, 'size_bytes': len(data),
                                    'sha256': hashlib.sha256(data).hexdigest()}, sort_keys=True))
    else:
        print('ABSENT ' + relative)
submission = basin / 'control/submission.json'
if not submission.is_file() or submission.is_symlink():
    print('SUBMISSION_RECEIPT_ABSENT')
    print('ONE20_STATUS_QUERY_END')
    raise SystemExit(0)
value = json.loads(submission.read_text(encoding='utf-8'))
match = re.fullmatch(r'Submitted batch job ([0-9]+)\s*', value.get('stdout', ''))
if value.get('basin_id') != '01142500' or value.get('returncode') != 0 or match is None:
    print('SUBMISSION_RECEIPT_AMBIGUOUS')
    print('ONE20_STATUS_QUERY_END')
    raise SystemExit(0)
job = match.group(1)
print('JOB_ID=' + job)
for label, command in (
    ('ACCOUNTING', ['sacct', '-X', '-j', job, '-P', '-n', '--format=JobID,JobName,Partition,AllocCPUS,ReqCPUS,AllocTRES,ReqTRES,ElapsedRaw,State,ExitCode']),
    ('QUEUE', ['squeue', '-j', job, '-h', '-o', '%i|%j|%T|%R']),
):
    result = subprocess.run(command, text=True, capture_output=True, timeout=30)
    print(label + '_RETURN_CODE=' + str(result.returncode))
    print(label + '_STDOUT=' + json.dumps(result.stdout[-3000:]))
    print(label + '_STDERR=' + json.dumps(result.stderr[-1000:]))
for suffix in ('out', 'err'):
    path = phase / 'logs' / f'job-{job}.{suffix}'
    if path.exists() or path.is_symlink():
        if not stat.S_ISREG(path.lstat().st_mode):
            raise RuntimeError('linked or nonregular job log')
        data = path.read_bytes()
        print('LOG ' + json.dumps({'path': 'logs/' + path.name, 'size_bytes': len(data),
                                   'sha256': hashlib.sha256(data).hexdigest(),
                                   'tail': data[-2000:].decode('utf-8', errors='replace')}, sort_keys=True))
print('ONE20_STATUS_QUERY_END')
PY
