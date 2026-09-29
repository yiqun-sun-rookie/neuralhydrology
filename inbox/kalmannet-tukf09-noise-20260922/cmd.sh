#!/usr/bin/env bash
set -euo pipefail
export PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1 PYTEST_DISABLE_PLUGIN_AUTOLOAD=1
export OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1
export MKL_THREADING_LAYER=GNU MKL_SERVICE_FORCE_INTEL=1 CUDA_VISIBLE_DEVICES='' CUDA_CACHE_DISABLE=1
phase='/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/full_budget_01142500_20260929_attempt2'
old='/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/full_budget_01142500_20260928_attempt1/bundle'
private='/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r14_20260909/runtime_v2r14/pysite'
export PYTHONPATH="$old/vendor:$private:$old:$old/hpc"

/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python -B - <<'PY'
import hashlib
import json
import os
from pathlib import Path
import pwd
import re
import subprocess
import sys

phase = Path('/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/full_budget_01142500_20260929_attempt2')
old = Path('/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/full_budget_01142500_20260928_attempt1/bundle')
private = Path('/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r14_20260909/runtime_v2r14/pysite').resolve()
control = phase / 'basin_01142500/control'
manifest_path = phase / 'payload_manifest.json'
wrapper = phase / 'tukf09_full_budget_01142500_20260929.py'
slurm = phase / 'full_budget_01142500_20260929.slurm'
attempt_path = control / 'submission_attempt.json'
receipt_path = control / 'submission.json'
staged_receipt_sha = '999b66eeefcb942fde47ab95570d2d2b85d18217fbc9cd52a4c0eaf677722526'
authorization_sha = 'b7ed240ce5d0723c050127074f11e4230bccda890071f8c481493525eef81b95'

def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def exclusive_json(path, value):
    with path.open('x', encoding='utf-8') as stream:
        json.dump(value, stream, sort_keys=True, separators=(',', ':'), allow_nan=False)
        stream.write('\n')
        stream.flush()
        os.fsync(stream.fileno())

print('FULL_BUDGET_ATTEMPT2_ONE_SUBMISSION_PREFLIGHT_BEGIN basin=01142500', flush=True)
if pwd.getpwuid(os.getuid()).pw_name != 'sunyiq':
    raise SystemExit('wrong remote account')
for directory in (phase, old, control, phase / 'logs', phase / 'cache', phase / 'tmp'):
    if directory.is_symlink() or not directory.is_dir():
        raise SystemExit('missing or linked isolated directory: ' + str(directory))
if {path.name for path in control.iterdir()} != {'deployment.json'}:
    raise SystemExit('one full-budget submission opportunity already consumed or control changed')
if (phase / 'basin_01142500/run').exists() or (phase / 'basin_01142500/run').is_symlink():
    raise SystemExit('run path exists before unique scheduler submission')
expected = {
    manifest_path: 'ccf02a35c7f0c4e882a007de46512fd1b1556d38ccd350b9f2fee9533cd8a2cc',
    wrapper: '52a79db0169082449c8ea10548f957a7f1a38b4a9fdba84eefa96b5a188cf60a',
    slurm: 'b5c63276ba806f4c334486d57af9cb64367c40ac470563fdcf9e913f3038e364',
    old / 'bundle_manifest.json': '4ebee2dcbd215e9751c86ca9895b84090956e7857d84b524fc87d60a3ea6afa1',
    old / 'hpc/tukf09_455_scaled_noise_common_v1.py': 'b4b70d97e4fdeca92ef1a7a8a6335a41d45acead5b40db5bdf1ab92ff70a3a5e',
    old / 'hpc/tukf09_455_scaled_noise_local_transfer_contract_v1.json': '27239212680bd370bd76f40e53337b7d68d80cbe4dc01feac2164bab4917f8a1',
}
for path, expected_sha in expected.items():
    if path.is_symlink() or not path.is_file() or digest(path) != expected_sha:
        raise SystemExit('staged or frozen fingerprint changed: ' + str(path))
manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
if (manifest.get('basin_id') != '01142500' or manifest.get('dimension') != 20
        or manifest.get('maximum_new_submissions') != 1 or manifest.get('wall_seconds') != 28800
        or manifest.get('partition') != 'hcpu48y' or manifest.get('cpus_per_task') != 1
        or manifest.get('frozen_local_checkpoint_selection_authorized') is not True
        or manifest.get('formal_evaluation_authorized') is not False
        or manifest.get('other_basin_authorized') is not False
        or manifest.get('automatic_retry_authorized') is not False
        or manifest.get('scientific_contract_changes_authorized') is not False
        or manifest.get('old_evidence_overwrite_authorized') is not False):
    raise SystemExit('staged payload scope changed')
deployment = json.loads((control / 'deployment.json').read_text(encoding='utf-8'))
if (deployment.get('status') != 'ONE_FULL_BUDGET_ATTEMPT2_STAGED_NOT_SUBMITTED'
        or deployment.get('scheduler_submission_performed') is not False
        or deployment.get('manifest_sha256') != digest(manifest_path)):
    raise SystemExit('exclusive deployment record changed')
import numpy as np
import torch
from hpc import tukf09_455_scaled_noise_common_v1 as frozen
frozen.configure_single_thread_execution()
if (not sys.version.startswith('3.11.13') or np.__version__ != '1.26.4'
        or not torch.__version__.startswith('2.2.2')
        or not Path(np.__file__).resolve().is_relative_to(private)
        or not Path(torch.__file__).resolve().is_relative_to(private)
        or torch.get_num_threads() != 1 or torch.get_num_interop_threads() != 1
        or Path(frozen.__file__).resolve() != (old / 'hpc/tukf09_455_scaled_noise_common_v1.py').resolve()):
    raise SystemExit('intended runtime changed after staged preflight')
partition = subprocess.run(['scontrol', 'show', 'partition', 'hcpu48y', '-o'], check=True,
                           text=True, capture_output=True, timeout=30).stdout.strip()
if ' State=UP ' not in (' ' + partition + ' ') or ' OverSubscribe=NO ' not in (' ' + partition + ' '):
    raise SystemExit('partition unavailable or allocation mode changed')
queue = subprocess.run(['squeue', '-u', 'sunyiq', '-h', '-o', '%i|%j|%T|%R'], check=True,
                       text=True, capture_output=True, timeout=30).stdout
if any('|tukf09-noise-' in line for line in queue.splitlines()):
    raise SystemExit('another scaled-noise job exists; unique submission prohibited')
print('FULL_BUDGET_ATTEMPT2_ONE_SUBMISSION_PREFLIGHT_PASS', flush=True)
exclusive_json(attempt_path, {
    'status': 'ONE_FULL_BUDGET_ATTEMPT2_SUBMISSION_CONSUMED_OUTCOME_UNKNOWN_UNTIL_RECEIPT',
    'basin_id': '01142500', 'dimension': 20, 'wall_seconds': 28800, 'requested_cpus': 1,
    'maximum_scheduler_billed_core_hours_if_billing_one_core': 8,
    'worst_case_48_core_node_hours': 384,
    'school_monetary_charge_rule_verified': False,
    'user_authorization_record_sha256': authorization_sha,
    'staged_runtime_receipt_sha256': staged_receipt_sha,
    'manifest_sha256': digest(manifest_path), 'wrapper_sha256': digest(wrapper),
    'slurm_script_sha256': digest(slurm), 'automatic_retry_authorized': False,
    'formal_evaluation_authorized': False, 'other_basin_authorized': False,
    'own_queue_before': queue, 'partition_before': partition,
})
print('FULL_BUDGET_ATTEMPT2_ONE_SUBMISSION_ATTEMPT_CONSUMED', flush=True)
result = subprocess.run(['sbatch', '--parsable', str(slurm)], text=True, capture_output=True, timeout=30)
print('SBATCH_RETURN_CODE=' + str(result.returncode), flush=True)
print('SBATCH_STDOUT=' + repr(result.stdout), flush=True)
print('SBATCH_STDERR=' + repr(result.stderr), flush=True)
if result.returncode != 0:
    raise SystemExit('unique scheduler request failed; no automatic retry')
raw_job = result.stdout.strip()
if not re.fullmatch(r'[0-9]+(?:;[A-Za-z0-9_.-]+)?', raw_job):
    raise SystemExit('scheduler accepted state ambiguous; inspect separately without retry')
job_id = raw_job.split(';', 1)[0]
exclusive_json(receipt_path, {
    'status': 'ONE_FULL_BUDGET_ATTEMPT2_SCHEDULER_SUBMISSION_CONFIRMED_NOT_MODEL_COMPLETION',
    'basin_id': '01142500', 'dimension': 20, 'job_id': job_id, 'sbatch_raw': raw_job,
    'manifest_sha256': digest(manifest_path), 'wrapper_sha256': digest(wrapper),
    'slurm_script_sha256': digest(slurm),
    'user_authorization_record_sha256': authorization_sha,
    'staged_runtime_receipt_sha256': staged_receipt_sha,
    'automatic_retry_authorized': False, 'formal_evaluation_authorized': False,
    'other_basin_authorized': False,
})
snapshot = subprocess.run(['squeue', '-j', job_id, '-h', '-o', '%i|%j|%T|%R'],
                          text=True, capture_output=True, timeout=30)
print('POST_SUBMIT_SQUEUE_RETURN_CODE=' + str(snapshot.returncode), flush=True)
print('POST_SUBMIT_SQUEUE=' + repr(snapshot.stdout), flush=True)
print('FULL_BUDGET_ATTEMPT2_ONE_SUBMISSION_CONFIRMED job=' + job_id, flush=True)
PY
