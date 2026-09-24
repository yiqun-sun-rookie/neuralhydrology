#!/usr/bin/env bash
set -eo pipefail
export PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1

/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python -I -B - <<'PY'
import base64
import hashlib
import json
from pathlib import Path

root = Path('/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/full_budget_v2')
relative_paths = (
    'control/deployed.json',
    'basin_01047000/control/submission_attempt.json',
    'basin_01047000/control/submission.json',
    'basin_01047000/control/original_tests.xml',
    'basin_01047000/control/new_gate_tests.xml',
    'logs/job-227494.out',
    'logs/job-227494.err',
)
for relative in relative_paths:
    path = root / relative
    if not path.is_file() or path.is_symlink():
        raise SystemExit('missing or linked fixed evidence file: ' + relative)
    data = path.read_bytes()
    print(json.dumps({
        'path': relative,
        'size_bytes': len(data),
        'sha256': hashlib.sha256(data).hexdigest(),
        'base64': base64.b64encode(data).decode('ascii'),
    }, sort_keys=True, separators=(',', ':')))
PY
