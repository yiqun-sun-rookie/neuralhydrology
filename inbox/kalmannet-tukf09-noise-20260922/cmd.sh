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
import subprocess
import sys

phase = Path('/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/full_budget_01142500_20260929_attempt2')
old = Path('/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/full_budget_01142500_20260928_attempt1/bundle')
private = Path('/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r14_20260909/runtime_v2r14/pysite').resolve()

def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

if pwd.getpwuid(os.getuid()).pw_name != 'sunyiq':
    raise SystemExit('wrong remote account')
for directory in (phase, phase / 'logs', phase / 'cache', phase / 'tmp', phase / 'basin_01142500', phase / 'basin_01142500/control', old):
    if directory.is_symlink() or not directory.is_dir():
        raise SystemExit('missing or linked staged directory: ' + str(directory))
if {path.name for path in phase.iterdir()} != {
    'logs', 'cache', 'tmp', 'basin_01142500', 'payload_manifest.json',
    'tukf09_full_budget_01142500_20260929.py', 'full_budget_01142500_20260929.slurm',
}:
    raise SystemExit('staged top-level member set changed')
if any(any((phase / name).iterdir()) for name in ('logs', 'cache', 'tmp')):
    raise SystemExit('staged logs, cache, or temporary directory is not empty')
control = phase / 'basin_01142500/control'
if {path.name for path in control.iterdir()} != {'deployment.json'}:
    raise SystemExit('staged control directory changed or submission already attempted')
if any((phase / 'basin_01142500' / name).exists() or (phase / 'basin_01142500' / name).is_symlink()
       for name in ('run', 'submission.json', 'submission_attempt.json')):
    raise SystemExit('staged run or submission evidence unexpectedly exists')
expected = {
    phase / 'payload_manifest.json': 'ccf02a35c7f0c4e882a007de46512fd1b1556d38ccd350b9f2fee9533cd8a2cc',
    phase / 'tukf09_full_budget_01142500_20260929.py': '52a79db0169082449c8ea10548f957a7f1a38b4a9fdba84eefa96b5a188cf60a',
    phase / 'full_budget_01142500_20260929.slurm': 'b5c63276ba806f4c334486d57af9cb64367c40ac470563fdcf9e913f3038e364',
    old / 'bundle_manifest.json': '4ebee2dcbd215e9751c86ca9895b84090956e7857d84b524fc87d60a3ea6afa1',
    old / 'hpc/tukf09_455_scaled_noise_common_v1.py': 'b4b70d97e4fdeca92ef1a7a8a6335a41d45acead5b40db5bdf1ab92ff70a3a5e',
    old / 'hpc/tukf09_455_scaled_noise_local_transfer_contract_v1.json': '27239212680bd370bd76f40e53337b7d68d80cbe4dc01feac2164bab4917f8a1',
}
for path, expected_sha in expected.items():
    if path.is_symlink() or not path.is_file() or digest(path) != expected_sha:
        raise SystemExit('staged or sealed fingerprint changed: ' + str(path))
manifest = json.loads((phase / 'payload_manifest.json').read_text(encoding='utf-8'))
if (manifest.get('basin_id') != '01142500' or manifest.get('dimension') != 20
        or manifest.get('maximum_new_submissions') != 1 or manifest.get('wall_seconds') != 28800
        or manifest.get('partition') != 'hcpu48y' or manifest.get('cpus_per_task') != 1
        or manifest.get('frozen_local_checkpoint_selection_authorized') is not True
        or manifest.get('formal_evaluation_authorized') is not False
        or manifest.get('other_basin_authorized') is not False
        or manifest.get('automatic_retry_authorized') is not False
        or manifest.get('scientific_contract_changes_authorized') is not False
        or manifest.get('old_evidence_overwrite_authorized') is not False):
    raise SystemExit('staged manifest scope changed')
deployment = json.loads((control / 'deployment.json').read_text(encoding='utf-8'))
if (deployment.get('status') != 'ONE_FULL_BUDGET_ATTEMPT2_STAGED_NOT_SUBMITTED'
        or deployment.get('archive_sha256') != '38d719ea23d2e95b7a8929ce341709dd4d60958b60ef79e37bb8a5391a5bce5b'
        or deployment.get('manifest_sha256') != expected[phase / 'payload_manifest.json']
        or deployment.get('scheduler_submission_performed') is not False):
    raise SystemExit('exclusive deployment record changed')
compile((phase / 'tukf09_full_budget_01142500_20260929.py').read_text(encoding='utf-8'),
        str(phase / 'tukf09_full_budget_01142500_20260929.py'), 'exec')
import numpy as np
import torch
from hpc import tukf09_455_scaled_noise_common_v1 as frozen
frozen.configure_single_thread_execution()
runtime = {
    'python': sys.version, 'python_executable': str(Path(sys.executable).resolve()),
    'numpy': np.__version__, 'numpy_path': str(Path(np.__file__).resolve()),
    'torch': torch.__version__, 'torch_path': str(Path(torch.__file__).resolve()),
    'torch_threads': torch.get_num_threads(), 'torch_interop_threads': torch.get_num_interop_threads(),
    'frozen_source_path': str(Path(frozen.__file__).resolve()),
}
if (not sys.version.startswith('3.11.13')
        or Path(sys.executable).resolve() != Path('/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python').resolve()
        or np.__version__ != '1.26.4' or not torch.__version__.startswith('2.2.2')
        or not Path(np.__file__).resolve().is_relative_to(private)
        or not Path(torch.__file__).resolve().is_relative_to(private)
        or torch.get_num_threads() != 1 or torch.get_num_interop_threads() != 1
        or Path(frozen.__file__).resolve() != (old / 'hpc/tukf09_455_scaled_noise_common_v1.py').resolve()):
    raise SystemExit('intended job runtime identity changed: ' + json.dumps(runtime, sort_keys=True))
partition = subprocess.run(['scontrol', 'show', 'partition', 'hcpu48y', '-o'], check=True,
                           text=True, capture_output=True, timeout=30).stdout.strip()
if ' State=UP ' not in (' ' + partition + ' ') or ' OverSubscribe=NO ' not in (' ' + partition + ' '):
    raise SystemExit('partition unavailable or allocation mode changed')
queue = subprocess.run(['squeue', '-u', 'sunyiq', '-h', '-o', '%i|%j|%T|%R'], check=True,
                       text=True, capture_output=True, timeout=30).stdout
if any('|tukf09-noise-' in line for line in queue.splitlines()):
    raise SystemExit('another scaled-noise job is active')
print('FULL_BUDGET_ATTEMPT2_STAGED_READONLY_PREFLIGHT ' + json.dumps({
    'status': 'PASS_STAGED_NOT_SUBMITTED', 'basin_id': '01142500',
    'manifest_sha256': expected[phase / 'payload_manifest.json'],
    'wrapper_sha256': expected[phase / 'tukf09_full_budget_01142500_20260929.py'],
    'slurm_sha256': expected[phase / 'full_budget_01142500_20260929.slurm'],
    'runtime': runtime, 'partition': partition, 'own_queue': queue,
    'scheduler_submission_performed': False, 'model_execution_performed': False,
    'evaluation_array_reads': 0,
}, sort_keys=True))
PY
