#!/bin/bash
set -euo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -I -B - <<'ZJ_FAIR_STATUS'
from pathlib import Path
import hashlib
import json
import subprocess

root = Path('/data1/home/sunyiq/zhenjiang_fair_comparison_20260928_002')
job = '229380'
expected_protocol = 'c12a304d42928fa819fe1504dbc59f00ee0bef22436a97679886b04476cd8254'
expected_attempt = '97d06e3d580da96f93e6505b32849f24f212aa7fa4841558d959bef498a07d16'

def small(path, maximum=16384):
    full = root / path
    if not full.exists():
        return None
    if full.is_symlink() or not full.is_file() or full.stat().st_size > maximum:
        raise ValueError('status metadata type or size differs: ' + path)
    return json.loads(full.read_bytes())

submitted = small('submission/submitted.json')
if (submitted is None or submitted['job_id'] != job or
        submitted['protocol_sha256'] != expected_protocol or
        submitted['attempt_sha256'] != expected_attempt):
    raise ValueError('status job differs from exclusive submission')
scheduler = {}
for name, args in (
    ('queue', ['squeue', '-j', job, '-h', '-o', '%i|%T|%M|%R']),
    ('accounting', ['sacct', '-j', job, '-n', '-P',
                    '--format=JobID,State,ExitCode,Elapsed,AllocTRES'])):
    result = subprocess.run(args, capture_output=True, text=True, timeout=15,
                            check=False)
    if len(result.stdout) + len(result.stderr) > 12000:
        raise ValueError('bounded scheduler reply exceeded')
    scheduler[name] = {'returncode': result.returncode,
                       'stdout': result.stdout, 'stderr': result.stderr}

preflight = small('preflight/result.json', 65536)
decision = small('reports/compute_decision.json', 16384)
attempt = small('run/separate_available/attempt.json')
failure = small('run/separate_available/failure.json', 16384)
complete = small('run/separate_available/complete.json', 16384)
progress = []
for station in ('nanjing', 'zhenjiang', 'jiangyin', 'xuliujing'):
    for seed in (17, 29, 43):
        folder = root / 'run/separate_available' / station / str(seed)
        records = [p for p in folder.glob('epoch_*.json')
                   if p.stem[6:].isdigit()] if folder.is_dir() else []
        latest = max(records, key=lambda p: int(p.stem[6:])) if records else None
        progress.append({'station': station, 'seed': seed, 'epoch_records': len(records),
                         'latest_epoch': int(latest.stem[6:]) if latest else None})
log_path = root / 'slurm' / ('job_' + job + '.log')
log_tail = None
if log_path.is_file() and not log_path.is_symlink():
    if log_path.stat().st_size > 20_000_000:
        raise ValueError('job log exceeds bounded status policy')
    with log_path.open('rb') as stream:
        stream.seek(max(0, log_path.stat().st_size - 4096))
        log_tail = stream.read(4096).decode(errors='replace')[-4096:]
print(json.dumps({'job_id': job, 'scheduler': scheduler,
                  'preflight_status': preflight['status'] if preflight else None,
                  'preflight_failure': small('preflight/failure.json', 16384),
                  'decision': decision['decisions']['separate_available'] if decision else None,
                  'attempt': attempt, 'failure': failure, 'complete': complete,
                  'progress': progress, 'log_tail': log_tail}, sort_keys=True))
ZJ_FAIR_STATUS
