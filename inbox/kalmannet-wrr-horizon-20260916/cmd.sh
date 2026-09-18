#!/bin/bash
set -eo pipefail
/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python -I -B - <<'PY'
"""Read existing scheduler records and small metadata files; no model execution."""
import hashlib
import json
import math
import subprocess
from datetime import datetime, timezone
from pathlib import Path


def command(args):
    result = subprocess.run(args, capture_output=True, text=True, timeout=35)
    return {"returncode": result.returncode, "stdout": result.stdout, "stderr": result.stderr}


def safe(value):
    if isinstance(value, float) and not math.isfinite(value):
        return str(value)
    if isinstance(value, dict):
        return {key: safe(item) for key, item in value.items()}
    if isinstance(value, list):
        return [safe(item) for item in value]
    return value


root = Path('/data1/home/sunyiq/kalmannet_wrr_training_horizon_20260916')
repo = root / 'repo'
pair = repo / 'artifacts/training_horizon_common_origins_v2/seed42'
report = {
    'observed_at_utc': datetime.now(timezone.utc).isoformat(),
    'read_only': True,
    'root': str(root),
    'root_exists': root.is_dir(),
    'job_id': 226070,
    'user_queue': command(['squeue', '-u', 'sunyiq', '-h', '-o', '%i|%j|%T|%P|%M|%R']),
    'scheduler_history': command(['sacct', '-X', '-j', '226070', '-n', '-P',
                                 '--format=JobID%40,JobName%50,State%40,ExitCode,Start,End,Elapsed,NodeList']),
    'job_detail': command(['scontrol', 'show', 'job', '226070']),
    'files': {},
}
paths = [repo / 'artifacts/hpc_execution/status.json', pair / 'status.json', pair / 'preflight.json']
for arm in ['output12', 'output25']:
    paths.extend([pair / arm / 'status.json', pair / arm / 'selection.json'])
    epoch_files = sorted((pair / arm).glob('epoch_*.json'))
    report[arm + '_epoch_record_count'] = len(epoch_files)
    if epoch_files:
        paths.append(epoch_files[-1])
for path in paths:
    entry = {'exists': path.is_file()}
    if path.is_file():
        if not path.resolve().is_relative_to(root.resolve()):
            raise RuntimeError('Metadata path escaped the registered experiment')
        raw = path.read_bytes()
        if len(raw) > 3_000_000:
            raise RuntimeError('Unexpected metadata size')
        entry.update(bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest(),
                     modified_at_utc=datetime.fromtimestamp(path.stat().st_mtime, timezone.utc).isoformat(),
                     content=json.loads(raw))
    report['files'][str(path.relative_to(root))] = entry
report['log_tails'] = {}
for name in ['job_226070.out', 'job_226070.err']:
    path = root / 'logs' / name
    report['log_tails'][name] = command(['tail', '-n', '35', str(path)]) if path.is_file() else {'exists': False}
print(json.dumps(safe(report), sort_keys=True, allow_nan=False))

PY
