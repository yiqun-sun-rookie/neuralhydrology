#!/usr/bin/env bash
set -euo pipefail
export PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1

/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python -B - <<'PY'
import hashlib
import json
from pathlib import Path
import subprocess

job_id = '231213'
phase = Path('/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/full_budget_01142500_20260929_attempt2')
control = phase / 'basin_01142500/control'
run = phase / 'basin_01142500/run'

def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def record(path):
    if path.is_symlink():
        raise SystemExit('linked evidence forbidden: ' + str(path))
    if not path.exists():
        return None
    if not path.is_file():
        raise SystemExit('expected evidence file: ' + str(path))
    return {'sha256': digest(path), 'size_bytes': path.stat().st_size}

squeue = subprocess.run(['squeue', '-j', job_id, '-h', '-o', '%i|%j|%T|%R|%M|%S'],
                        text=True, capture_output=True, timeout=30)
sacct = subprocess.run(['sacct', '-X', '-j', job_id, '-P', '-n',
                        '--format=JobID,JobName,Partition,AllocCPUS,ReqCPUS,AllocTRES,ReqTRES,ElapsedRaw,State,ExitCode,Start,End,Timelimit'],
                       text=True, capture_output=True, timeout=30)
if squeue.returncode != 0 or sacct.returncode != 0:
    raise SystemExit('scheduler read-only query failed')
submission = json.loads((control / 'submission.json').read_text(encoding='utf-8'))
attempt = json.loads((control / 'submission_attempt.json').read_text(encoding='utf-8'))
if (submission.get('job_id') != job_id
        or submission.get('status') != 'ONE_FULL_BUDGET_ATTEMPT2_SCHEDULER_SUBMISSION_CONFIRMED_NOT_MODEL_COMPLETION'
        or attempt.get('status') != 'ONE_FULL_BUDGET_ATTEMPT2_SUBMISSION_CONSUMED_OUTCOME_UNKNOWN_UNTIL_RECEIPT'):
    raise SystemExit('unique submission evidence changed')
progress_path = run / 'progress/progress.jsonl'
progress = {'exists': False, 'events': 0, 'checkpoints': 0, 'gradient_updates': 0, 'last_events': []}
if progress_path.exists() or progress_path.is_symlink():
    if progress_path.is_symlink() or not progress_path.is_file():
        raise SystemExit('progress path linked or not a file')
    lines = progress_path.read_text(encoding='utf-8').splitlines()
    events = [json.loads(line) for line in lines]
    if [item.get('event_index') for item in events] != list(range(1, len(events) + 1)):
        raise SystemExit('progress event sequence changed')
    progress = {
        'exists': True, 'events': len(events),
        'checkpoints': sum(item.get('type') == 'checkpoint' for item in events),
        'gradient_updates': sum(item.get('type') == 'gradient_update' for item in events),
        'last_events': events[-2:],
        'record': record(progress_path),
    }
files = {}
for relative in (
    'basin_01142500/control/deployment.json',
    'basin_01142500/control/submission_attempt.json',
    'basin_01142500/control/submission.json',
    'basin_01142500/control/job_gate.json',
    'basin_01142500/control/attempt2_gate.json',
    'basin_01142500/run/supervisor.json',
    'basin_01142500/run/model/started.json',
    'basin_01142500/run/model/history.npz',
    'basin_01142500/run/model/summary.json',
    'basin_01142500/run/model/manifest.final.sha256.json',
    'basin_01142500/run/progress/progress_complete.json',
    'basin_01142500/run/progress/progress_manifest.sha256.json',
    f'logs/job-{job_id}.out', f'logs/job-{job_id}.err',
):
    files[relative] = record(phase / relative)
log_tails = {}
for suffix in ('out', 'err'):
    path = phase / 'logs' / f'job-{job_id}.{suffix}'
    if path.is_file() and not path.is_symlink():
        lines = path.read_text(encoding='utf-8', errors='replace').splitlines()
        log_tails[suffix] = lines[-20:]
print('FULL_BUDGET_ATTEMPT2_READONLY_STATUS ' + json.dumps({
    'job_id': job_id, 'squeue_return_code': squeue.returncode, 'squeue': squeue.stdout,
    'sacct': sacct.stdout, 'progress': progress, 'files': files, 'log_tails': log_tails,
    'scheduler_mutation_performed': False, 'model_execution_requested_by_status_query': False,
    'formal_evaluation_performed': False,
}, sort_keys=True))
PY
