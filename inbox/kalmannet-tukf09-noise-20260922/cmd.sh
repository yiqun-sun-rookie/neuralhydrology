#!/usr/bin/env bash
set -euo pipefail
export PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1

/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python -B - <<'PY'
import hashlib
import json
from pathlib import Path
import stat
import subprocess

phase = Path('/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/full_budget_01142500_20260928_attempt1')
job = '229133'
print('ONE20_COMPLETION_DIAGNOSIS_BEGIN job=' + job)
for relative in ('basin_01142500/run/supervisor.json',
                 'basin_01142500/run/model/started.json',
                 'basin_01142500/run/model/summary.json',
                 'basin_01142500/run/model/manifest.final.sha256.json',
                 'basin_01142500/control/job_gate.json',
                 'logs/job-229133.out', 'logs/job-229133.err'):
    path = phase / relative
    if not path.exists() and not path.is_symlink():
        print('ABSENT ' + relative)
        continue
    if not stat.S_ISREG(path.lstat().st_mode):
        raise RuntimeError('linked or nonregular evidence: ' + relative)
    data = path.read_bytes()
    info = {'path': relative, 'size_bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
    if relative.endswith('.json'):
        info['content'] = json.loads(data)
    else:
        info['tail'] = data[-10000:].decode('utf-8', errors='replace')
    print('EVIDENCE ' + json.dumps(info, sort_keys=True, separators=(',', ':')))
for label, command in (
    ('ACCOUNTING', ['sacct', '-X', '-j', job, '-P', '-n', '--format=JobID,JobName,Partition,AllocCPUS,ReqCPUS,AllocTRES,ReqTRES,ElapsedRaw,State,ExitCode']),
    ('QUEUE', ['squeue', '-j', job, '-h', '-o', '%i|%j|%T|%R']),
):
    result = subprocess.run(command, text=True, capture_output=True, timeout=30)
    print(label + ' ' + json.dumps({'returncode': result.returncode,
                                    'stdout': result.stdout[-3000:],
                                    'stderr': result.stderr[-1000:]}, sort_keys=True))
print('ONE20_COMPLETION_DIAGNOSIS_END')
PY
