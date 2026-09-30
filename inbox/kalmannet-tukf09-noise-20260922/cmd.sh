#!/usr/bin/env bash
set -euo pipefail
export PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1

/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python -B - <<'PY'
import hashlib
import json
import os
from pathlib import Path
import pwd
import subprocess

phase = Path('/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_local_selection_remaining_453_20260930_attempt1/canary11')
parent = phase.parent
old = Path('/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/full_budget_01142500_20260928_attempt1/bundle')
previous = Path('/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/full_budget_01142500_20260929_attempt2/tukf09_full_budget_01142500_20260929.py')

def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

if pwd.getpwuid(os.getuid()).pw_name != 'sunyiq':
    raise SystemExit('wrong remote account')
if phase.exists() or phase.is_symlink():
    raise SystemExit('new canary phase is already occupied')
if parent.exists() and (parent.is_symlink() or not parent.is_dir()):
    raise SystemExit('new canary parent is linked or not a directory')
for path, expected in (
    (old / 'bundle_manifest.json', '4ebee2dcbd215e9751c86ca9895b84090956e7857d84b524fc87d60a3ea6afa1'),
    (old / 'hpc/tukf09_455_scaled_noise_common_v1.py', 'b4b70d97e4fdeca92ef1a7a8a6335a41d45acead5b40db5bdf1ab92ff70a3a5e'),
    (old / 'hpc/tukf09_455_scaled_noise_local_transfer_contract_v1.json', '27239212680bd370bd76f40e53337b7d68d80cbe4dc01feac2164bab4917f8a1'),
    (previous, '52a79db0169082449c8ea10548f957a7f1a38b4a9fdba84eefa96b5a188cf60a'),
):
    if path.is_symlink() or not path.is_file() or digest(path) != expected:
        raise SystemExit('sealed remote prerequisite changed: ' + str(path))
partition = subprocess.run(['scontrol', 'show', 'partition', 'hcpu48y', '-o'], check=True,
                           text=True, capture_output=True, timeout=30).stdout.strip()
if ' State=UP ' not in (' ' + partition + ' ') or ' OverSubscribe=NO ' not in (' ' + partition + ' '):
    raise SystemExit('processor partition unavailable or allocation mode changed')
queue = subprocess.run(['squeue', '-u', 'sunyiq', '-h', '-o', '%i|%j|%T|%R|%M'], check=True,
                       text=True, capture_output=True, timeout=30).stdout
space = subprocess.run(['df', '-Pk', str(old.parent)], check=True, text=True,
                       capture_output=True, timeout=30).stdout
print('CANARY11_REMOTE_READONLY_PREFLIGHT_PASS ' + json.dumps({
    'phase_absent': True,
    'parent_exists': parent.exists(),
    'partition': partition,
    'own_queue': queue,
    'storage': space,
    'scheduler_submission_performed': False,
    'model_execution_performed': False,
    'evaluation_array_reads': 0,
    'formal_evaluation_performed': False,
}, sort_keys=True))
PY
