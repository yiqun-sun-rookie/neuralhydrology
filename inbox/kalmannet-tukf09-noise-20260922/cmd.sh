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

target = Path('/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/full_budget_01142500_20260929_attempt2')
old = Path('/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/full_budget_01142500_20260928_attempt1/bundle')
diagnostic = Path('/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/timing_probe_01142500_20260929_attempt2')

def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

if pwd.getpwuid(os.getuid()).pw_name != 'sunyiq':
    raise SystemExit('wrong remote account')
if target.exists() or target.is_symlink():
    raise SystemExit('new full-budget root occupied or linked')
if target.parent.is_symlink() or not target.parent.is_dir():
    raise SystemExit('new full-budget parent missing or linked')
expected = {
    old / 'bundle_manifest.json': '4ebee2dcbd215e9751c86ca9895b84090956e7857d84b524fc87d60a3ea6afa1',
    old / 'hpc/tukf09_455_scaled_noise_common_v1.py': 'b4b70d97e4fdeca92ef1a7a8a6335a41d45acead5b40db5bdf1ab92ff70a3a5e',
    old / 'hpc/tukf09_455_scaled_noise_local_transfer_contract_v1.json': '27239212680bd370bd76f40e53337b7d68d80cbe4dc01feac2164bab4917f8a1',
    diagnostic / 'payload_manifest.json': '47667a0cdb13496aab453d3c4c686ee44f23452c0483321ffcd2784e72da34d0',
    diagnostic / 'basin_01142500/run/model/diagnostic_complete.json': '70c8359901332536be84709beb082b4d5a798dd93d36c8df2eb1cbe261fc5eb0',
    diagnostic / 'basin_01142500/run/model/diagnostic_manifest.sha256.json': '5dbfee4a2a1c3394544b7d0f123957232accae6e9a3d7882a87329e6a8b9b5eb',
}
for path, expected_sha in expected.items():
    if path.is_symlink() or not path.is_file() or digest(path) != expected_sha:
        raise SystemExit('sealed prerequisite changed: ' + str(path))
complete = json.loads((diagnostic / 'basin_01142500/run/model/diagnostic_complete.json').read_text(encoding='utf-8'))
if complete != {
    'status': 'DIAGNOSTIC_64_CHECKPOINTS_64_UPDATES_NOT_FORMAL_SELECTION',
    'basin_id': '01142500', 'completed_checkpoints': 64, 'completed_gradient_updates': 64,
    'training_objective_calls': 64, 'validation_objective_calls': 64,
    'next_call_stopped_before_execution': 'training_65', 'evaluation_array_reads': 0,
    'formal_selection': False, 'scientific_performance_claim': False,
}:
    raise SystemExit('diagnostic completion record changed')
model = diagnostic / 'basin_01142500/run/model'
calls = sorted(model.glob('call_*.json'))
updates = sorted(model.glob('update_*.json'))
if len(calls) != 128 or len(updates) != 64 or any(p.is_symlink() or not p.is_file() for p in calls + updates):
    raise SystemExit('diagnostic progress evidence changed')
partition = subprocess.run(['scontrol', 'show', 'partition', 'hcpu48y', '-o'], check=True,
                           text=True, capture_output=True, timeout=30).stdout.strip()
if ' State=UP ' not in (' ' + partition + ' ') or ' OverSubscribe=NO ' not in (' ' + partition + ' '):
    raise SystemExit('hcpu48y unavailable or allocation mode changed')
queue = subprocess.run(['squeue', '-u', 'sunyiq', '-h', '-o', '%i|%j|%T|%R'], check=True,
                       text=True, capture_output=True, timeout=30).stdout
if any('|tukf09-noise-' in line for line in queue.splitlines()):
    raise SystemExit('another scaled-noise job is active')
accounting = {}
for job in ('229133', '231059'):
    result = subprocess.run(['sacct', '-X', '-j', job, '-P', '-n',
                             '--format=JobID,JobName,Partition,AllocCPUS,ReqCPUS,AllocTRES,ReqTRES,ElapsedRaw,State,ExitCode,Start,End,Timelimit'],
                            check=True, text=True, capture_output=True, timeout=30)
    rows = [line for line in result.stdout.splitlines() if line.strip()]
    if len(rows) != 1:
        raise SystemExit('scheduler prerequisite record is not unique: ' + job)
    accounting[job] = rows[0]
if '|14343|FAILED|1:0|' not in accounting['229133'] or '|1978|COMPLETED|0:0|' not in accounting['231059']:
    raise SystemExit('scheduler prerequisite terminal state changed')
runtime = subprocess.run([
    '/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python', '-B', '-c',
    "import json,numpy,torch,sys; print(json.dumps({'python':sys.version,'numpy':numpy.__version__,'torch':torch.__version__},sort_keys=True))"
], check=True, text=True, capture_output=True, timeout=60).stdout.strip()
print('FULL_BUDGET_ATTEMPT2_READONLY_PREFLIGHT ' + json.dumps({
    'status': 'PASS_NOT_DEPLOYED_NOT_SUBMITTED',
    'target_absent': True,
    'old_bundle_manifest_sha256': expected[old / 'bundle_manifest.json'],
    'diagnostic_complete_sha256': expected[diagnostic / 'basin_01142500/run/model/diagnostic_complete.json'],
    'diagnostic_calls': len(calls), 'diagnostic_updates': len(updates),
    'partition': partition, 'own_queue': queue, 'accounting': accounting, 'runtime': json.loads(runtime),
    'maximum_one_core_hours': 8, 'worst_case_48_core_node_hours': 384,
    'scheduler_submission_performed': False,
}, sort_keys=True))
PY
