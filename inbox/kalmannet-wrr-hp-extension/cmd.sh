#!/usr/bin/env bash
# Read-only scheduler-interface diagnosis. No training or admission writes.
set -euo pipefail
python3 -B - <<'PY'
import datetime
import json
import subprocess

parent = '223848'
commands = [
    ['sacct', '--version'],
    ['sacct', '--helpformat'],
    ['sacct', '--help'],
    ['sacct', '-X', '--array', '--noheader', '--parsable2', '--jobs', parent,
     '--format', 'JobID%64,JobIDRaw%32,State%32,ExitCode,ElapsedRaw'],
    ['sacct', '-X', '--noheader', '--parsable2', '--jobs', parent,
     '--format', 'JobID%64,JobIDRaw%32,State%32,ExitCode,ElapsedRaw'],
    ['squeue', '-r', '-h', '-u', 'sunyiq', '-o', '%i|%T|%Z'],
]
results = []
for command in commands:
    try:
        result = subprocess.run(command, capture_output=True, text=True, check=False, timeout=45)
        results.append({'command': command, 'returncode': result.returncode,
                        'stdout': result.stdout, 'stderr': result.stderr})
    except (OSError, subprocess.TimeoutExpired) as error:
        results.append({'command': command, 'error': type(error).__name__ + ': ' + str(error)})
print(json.dumps({'kind': 'READ_ONLY_SCHEDULER_DIAGNOSIS_NOT_ADMISSION',
                  'stage': 'A', 'parent_job': parent,
                  'observed_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                  'queries': results, 'new_jobs_submitted': 0,
                  'admission_written': False}, sort_keys=True))
PY
