#!/usr/bin/env bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python -B - <<'PY'
import json
from pathlib import Path
import re
import subprocess
root = Path('/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/narrow_probe_v2')
submission = json.loads((root/'control/submission.json').read_text())
match = re.fullmatch(r'Submitted batch job ([0-9]+)\s*', submission['stdout'])
if submission['returncode'] != 0 or match is None:
    raise RuntimeError('no uniquely confirmed job')
job = match.group(1)
print('CONFIRMED_JOB',job,flush=True)
for command in (['sacct','-j',job,'-n','-P','--format=JobIDRaw,JobName,State,ExitCode,Elapsed,AllocCPUS,NodeList'],
                ['squeue','-u','sunyiq','-h','-o','%i|%j|%T|%R']):
    result = subprocess.run(command,text=True,capture_output=True,check=True)
    print(result.stdout,flush=True)
for relative in ('control/linux_tests.xml', 'run/supervisor.json', 'run/model/started.json',
                 'run/model/run_summary.json', 'run/model/manifest.final.sha256.json',
                 'run/stdout.log','run/stderr.log',f'logs/job-{job}.out',f'logs/job-{job}.err'):
    path = root/relative
    print('FILE',relative,'PRESENT' if path.is_file() else 'ABSENT',flush=True)
    if path.is_file():
        if path.stat().st_size > 200000:
            print('FILE_TOO_LARGE_FOR_INLINE_READ',path.stat().st_size,flush=True)
        else:
            print(path.read_text(errors='replace'),flush=True)
PY
