#!/usr/bin/env bash
set -euo pipefail
export PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1

/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python -B - <<'PY'
import hashlib
import json
import os
from pathlib import Path
import pwd
import re
import subprocess

phase = Path('/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/timing_probe_01142500_20260929_attempt2')
old = Path('/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/full_budget_01142500_20260928_attempt1/bundle')
control = phase / 'basin_01142500/control'
slurm = phase / 'timing_probe_01142500_20260929.slurm'
wrapper = phase / 'tukf09_timing_probe_01142500_20260929.py'
manifest_path = phase / 'payload_manifest.json'
attempt_path = control / 'submission_attempt.json'
receipt_path = control / 'submission.json'

def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def exclusive_json(path, value):
    with path.open('x', encoding='utf-8') as stream:
        json.dump(value, stream, sort_keys=True, separators=(',', ':'), allow_nan=False)
        stream.write('\n')
        stream.flush()
        os.fsync(stream.fileno())

print('TIMING_PROBE_ONE_SUBMISSION_PREFLIGHT_BEGIN basin=01142500', flush=True)
if pwd.getpwuid(os.getuid()).pw_name != 'sunyiq':
    raise SystemExit('wrong remote account')
for item in (phase, old, control, phase / 'logs', phase / 'tmp', phase / 'cache'):
    if item.is_symlink() or not item.is_dir():
        raise SystemExit('missing or linked isolated directory: ' + str(item))
for item in (attempt_path, receipt_path, phase / 'basin_01142500/run'):
    if item.exists() or item.is_symlink():
        raise SystemExit('one diagnostic submission opportunity already consumed or run exists: ' + str(item))
for item, expected in (
    (manifest_path, '47667a0cdb13496aab453d3c4c686ee44f23452c0483321ffcd2784e72da34d0'),
    (wrapper, '8b1eb7a0ed7f078b4e65b436676e685499388785bddb22f43ec0e3929969abb8'),
    (slurm, '67162aebf1ec4a2b2e0bd26904c4c8c81aed5a5ab60acccdd71b0d02d3a3e4e3'),
    (old / 'bundle_manifest.json', '4ebee2dcbd215e9751c86ca9895b84090956e7857d84b524fc87d60a3ea6afa1'),
    (old / 'hpc/tukf09_455_scaled_noise_common_v1.py', 'b4b70d97e4fdeca92ef1a7a8a6335a41d45acead5b40db5bdf1ab92ff70a3a5e'),
):
    if item.is_symlink() or not item.is_file() or digest(item) != expected:
        raise SystemExit('diagnostic or frozen input fingerprint changed: ' + str(item))
manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
if (manifest.get('basin_id') != '01142500' or manifest.get('remote_phase') != phase.as_posix()
        or manifest.get('maximum_new_submissions') != 1 or manifest.get('wall_seconds') != 7200
        or manifest.get('cpus_per_task') != 1 or manifest.get('formal_selection_authorized') is not False
        or manifest.get('formal_evaluation_authorized') is not False or manifest.get('other_basin_authorized') is not False
        or manifest.get('automatic_retry_authorized') is not False):
    raise SystemExit('diagnostic payload scope changed')
deployment = json.loads((control / 'deployment.json').read_text(encoding='utf-8'))
if (deployment.get('status') != 'ONE_TIMING_DIAGNOSTIC_STAGED_NOT_SUBMITTED'
        or deployment.get('scheduler_submission_performed') is not False
        or deployment.get('manifest_sha256') != digest(manifest_path)):
    raise SystemExit('exclusive diagnostic deployment record changed')
partition = subprocess.run(['scontrol', 'show', 'partition', 'hcpu48y', '-o'], check=True,
                           text=True, capture_output=True, timeout=30).stdout.strip()
if ' State=UP ' not in (' ' + partition + ' ') or ' OverSubscribe=NO ' not in (' ' + partition + ' '):
    raise SystemExit('diagnostic partition is not available as preflighted')
queue = subprocess.run(['squeue', '-u', 'sunyiq', '-h', '-o', '%i|%j|%T'], check=True,
                       text=True, capture_output=True, timeout=30).stdout
for line in queue.splitlines():
    fields = line.split('|')
    if len(fields) != 3:
        raise SystemExit('own queue format changed')
    if fields[1].startswith('tukf09-noise-'):
        raise SystemExit('another noise-stage job exists; one diagnostic submission prohibited')
print('TIMING_PROBE_ONE_SUBMISSION_PREFLIGHT_PASS', flush=True)
exclusive_json(attempt_path, {
    'status': 'ONE_DIAGNOSTIC_SUBMISSION_ATTEMPT_CONSUMED_OUTCOME_UNKNOWN_UNTIL_RECEIPT',
    'basin_id': '01142500', 'wall_seconds': 7200, 'requested_cpus': 1,
    'worst_case_accepted_core_hours': 96,
    'user_cost_risk_authorization_sha256': '78d6bf0a9dd858d9dc09c2e1718f83be222746c91049a3a59e54aba3339e86e9',
    'manifest_sha256': digest(manifest_path),
    'slurm_script_sha256': digest(slurm),
    'automatic_retry_authorized': False,
    'formal_selection_authorized': False,
    'formal_evaluation_authorized': False,
    'own_queue_before': queue,
    'partition_before': partition,
})
print('TIMING_PROBE_ONE_SUBMISSION_ATTEMPT_CONSUMED', flush=True)
result = subprocess.run(['sbatch', '--parsable', str(slurm)], text=True, capture_output=True, timeout=30)
print('SBATCH_RETURN_CODE=' + str(result.returncode), flush=True)
print('SBATCH_STDOUT=' + repr(result.stdout), flush=True)
print('SBATCH_STDERR=' + repr(result.stderr), flush=True)
if result.returncode != 0:
    raise SystemExit('one diagnostic scheduler request failed; no automatic retry')
job = result.stdout.strip()
if not re.fullmatch(r'[0-9]+(?:;[A-Za-z0-9_.-]+)?', job):
    raise SystemExit('scheduler accepted state ambiguous; inspect separately without retry')
job_id = job.split(';', 1)[0]
exclusive_json(receipt_path, {
    'status': 'ONE_TIMING_DIAGNOSTIC_SCHEDULER_SUBMISSION_CONFIRMED_NOT_MODEL_COMPLETION',
    'basin_id': '01142500', 'job_id': job_id, 'sbatch_raw': job,
    'manifest_sha256': digest(manifest_path),
    'user_cost_risk_authorization_sha256': '78d6bf0a9dd858d9dc09c2e1718f83be222746c91049a3a59e54aba3339e86e9',
    'automatic_retry_authorized': False,
    'formal_selection_authorized': False,
    'formal_evaluation_authorized': False,
})
print('TIMING_PROBE_ONE_SUBMISSION_CONFIRMED job=' + job_id, flush=True)
PY
