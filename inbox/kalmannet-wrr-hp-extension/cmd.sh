#!/usr/bin/env bash
# Read-only resource and exact original-job inspection for user-requested B retries.
set -euo pipefail
python3 -I -B - <<'PY'
import base64
import datetime
import gzip
import hashlib
import json
import pathlib
import subprocess

root = pathlib.Path('/data1/home/sunyiq/kalmannet_wrr_model_selection_20260908/stages/B')
assert root.is_dir() and not root.is_symlink() and root.resolve() == root
assert (root / 'array_job_id.txt').read_text().strip() == '224255'
manifest_bytes = (root / 'STAGE_B_MANIFEST.json').read_bytes()
assert hashlib.sha256(manifest_bytes).hexdigest() == 'c5f8d56480510729dd14d44cb00d5e703425ebdeb837b059b674998b425784b1'

queries = [
    ['sinfo', '-a', '-N', '-h', '-o', '%N|%P|%t|%G|%m|%f'],
    ['scontrol', 'show', 'partition', '-o'],
    ['sacctmgr', '-n', '-P', 'show', 'assoc', 'where', 'user=sunyiq',
     'format=Cluster,Account,User,Partition,QOS,DefaultQOS'],
    ['squeue', '-r', '-u', 'sunyiq', '-h', '-o', '%i|%j|%P|%T|%D|%b|%M|%R'],
    ['sacct', '-j', '224255', '-X', '-n', '-P',
     '--format=JobID,JobIDRaw,State,ExitCode,Elapsed,Start,End,NodeList,ReqTRES,AllocTRES'],
]
results = []
for argv in queries:
    try:
        response = subprocess.run(argv, text=True, capture_output=True, timeout=40, check=False)
        results.append({'command': argv, 'returncode': response.returncode,
                        'stdout': response.stdout, 'stderr': response.stderr})
    except subprocess.TimeoutExpired as exc:
        results.append({'command': argv, 'error': 'TimeoutExpired', 'timeout_seconds': exc.timeout})
report = {'kind': 'READ_ONLY_B_MEMORY_RESOURCE_PROBE', 'job_id': '224255',
          'observed_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'queries': results, 'new_jobs_submitted': 0, 'existing_jobs_changed': False,
          'data_or_checkpoint_tensors_loaded': False, 'remote_files_written': 0}
blob = json.dumps(report, sort_keys=True, separators=(',', ':')).encode()
print('RESOURCE_PROBE_GZIP_BASE64=' + base64.b64encode(gzip.compress(blob, mtime=0)).decode())
print('RESOURCE_PROBE_SUMMARY=' + json.dumps({'commands': len(results),
      'returncodes': [r.get('returncode') for r in results], 'new_jobs_submitted': 0}))
PY
