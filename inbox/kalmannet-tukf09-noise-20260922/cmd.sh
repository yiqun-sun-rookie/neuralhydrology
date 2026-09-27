#!/usr/bin/env bash
set -euo pipefail
export PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1

printf '%s\n' '=== FIRST-BASIN TERMINAL LOGS AND RESULT IDENTITIES ==='
date -u '+UTC=%Y-%m-%dT%H:%M:%SZ'
/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python -B - <<'PY'
import hashlib
import json
from pathlib import Path
import stat

phase = Path('/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/full_budget_integrated_release_20260927_attempt1')
basin = phase / 'basin_01047000'
files = (
    phase / 'logs/job-228327.out',
    phase / 'logs/job-228327.err',
    basin / 'run/stdout.log',
    basin / 'run/stderr.log',
    basin / 'run/supervisor.json',
    basin / 'control/job_gate.json',
    basin / 'run/model/started.json',
    basin / 'run/model/summary.json',
    basin / 'run/model/history.npz',
    basin / 'run/model/manifest.final.sha256.json',
)
for path in files:
    mode = path.lstat().st_mode
    if not stat.S_ISREG(mode):
        raise RuntimeError('expected regular unlinked evidence file: ' + str(path))
    with path.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    relative = path.relative_to(phase).as_posix()
    print('FILE ' + json.dumps({'path': relative, 'size_bytes': path.stat().st_size, 'sha256': digest}, sort_keys=True, separators=(',', ':')))
    if path.suffix in ('.out', '.err', '.log'):
        with path.open('rb') as stream:
            stream.seek(max(0, path.stat().st_size - 4000))
            tail = stream.read().decode('utf-8', errors='replace')
        print('TAIL ' + relative + ' ' + repr(tail))
summary = json.loads((basin / 'run/model/summary.json').read_text(encoding='utf-8'))
supervisor = json.loads((basin / 'run/supervisor.json').read_text(encoding='utf-8'))
print('COUNTS ' + json.dumps(summary.get('counts'), sort_keys=True, separators=(',', ':')))
print('SUPERVISOR ' + json.dumps({key: supervisor.get(key) for key in ('success', 'reason', 'exit_code', 'wall_seconds', 'peak_tree_rss_bytes', 'output_bytes')}, sort_keys=True, separators=(',', ':')))
print('READ_ONLY_FIRST_BASIN_TERMINAL_LOGS_COMPLETE')
PY
