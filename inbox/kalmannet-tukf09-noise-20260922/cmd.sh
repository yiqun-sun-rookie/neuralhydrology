#!/usr/bin/env bash
set -euo pipefail
export PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1

/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python -B - <<'PY'
import base64
import hashlib
import json
from pathlib import Path
import stat

phase = Path('/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/timing_probe_01142500_20260929_attempt2')
if phase.is_symlink() or not phase.is_dir():
    raise RuntimeError('isolated diagnostic root missing or linked')
paths = (
    'basin_01142500/control/original_tests.xml',
    'basin_01142500/control/output_guard_regression.xml',
    'basin_01142500/control/new_gate_tests.xml',
    'basin_01142500/control/tensor_tests/tensor_tests.xml',
    'basin_01142500/control/tensor_tests/supervisor.json',
    'basin_01142500/control/tensor_tests/stdout.log',
    'basin_01142500/control/tensor_tests/stderr.log',
    'basin_01142500/run/heartbeat.json',
    'basin_01142500/run/watchdog.stop',
    'basin_01142500/run/worker.pid',
)
print('TIMING_DIAGNOSTIC_TERMINAL_GATE_LOGS_BEGIN job=231059 expected=' + str(len(paths)))
total = 0
for relative in paths:
    path = phase / relative
    if not path.exists() and not path.is_symlink():
        print('ABSENT ' + relative)
        continue
    if not stat.S_ISREG(path.lstat().st_mode):
        raise RuntimeError('linked or nonregular terminal gate log: ' + relative)
    data = path.read_bytes()
    total += len(data)
    if len(data) > 400000 or total > 650000:
        raise RuntimeError('terminal gate log evidence exceeds retrieval bound')
    print('EVIDENCE ' + json.dumps({
        'path': relative,
        'size_bytes': len(data),
        'sha256': hashlib.sha256(data).hexdigest(),
        'base64': base64.b64encode(data).decode('ascii'),
    }, sort_keys=True, separators=(',', ':')))
print('TOTAL_BYTES=' + str(total))
print('TIMING_DIAGNOSTIC_TERMINAL_GATE_LOGS_END')
PY
