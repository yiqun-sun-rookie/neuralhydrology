#!/bin/bash
set -eo pipefail
export PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python -B - <<'PY'
import hashlib
import json
import os
from pathlib import Path
import pwd
import subprocess
phase=Path('/data1/home/sunyiq/kalmannet_tukf09_four_failed_basins_20261003_attempt1')
old=Path('/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/full_budget_01142500_20260928_attempt1/bundle')
previous=Path('/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/full_budget_01142500_20260929_attempt2/tukf09_full_budget_01142500_20260929.py')
if pwd.getpwuid(os.getuid()).pw_name != 'sunyiq' or phase.exists() or phase.is_symlink():
    raise SystemExit('wrong account or isolated destination occupied')
expected={
    old/'bundle_manifest.json':'4ebee2dcbd215e9751c86ca9895b84090956e7857d84b524fc87d60a3ea6afa1',
    old/'hpc/tukf09_455_scaled_noise_common_v1.py':'b4b70d97e4fdeca92ef1a7a8a6335a41d45acead5b40db5bdf1ab92ff70a3a5e',
    old/'hpc/tukf09_455_scaled_noise_local_transfer_contract_v1.json':'27239212680bd370bd76f40e53337b7d68d80cbe4dc01feac2164bab4917f8a1',
    previous:'52a79db0169082449c8ea10548f957a7f1a38b4a9fdba84eefa96b5a188cf60a',
}
for path,wanted in expected.items():
    if path.is_symlink() or not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest()!=wanted:
        raise SystemExit('frozen prerequisite changed: '+str(path))
partition=subprocess.run(['scontrol','show','partition','hcpu48y','-o'],check=True,text=True,capture_output=True,timeout=30).stdout.strip()
queue=subprocess.run(['squeue','-u','sunyiq','-h','-o','%i|%j|%T|%R'],check=True,text=True,capture_output=True,timeout=30).stdout.strip()
if ' State=UP ' not in ' '+partition+' ' or ' OverSubscribe=NO ' not in ' '+partition+' ':
    raise SystemExit('partition unavailable or allocation mode changed')
if any('|tukf09-noise-' in line for line in queue.splitlines()):
    raise SystemExit('another scaled-noise job is in flight')
print('FOUR_FAILED_READONLY_PREFLIGHT_PASS '+json.dumps({'new_destination_absent':True,'frozen_source_hashes_matched':len(expected),'partition':partition,'own_queue':queue,'scheduler_submissions':0,'model_executions':0,'evaluation_array_reads':0},sort_keys=True))
PY
