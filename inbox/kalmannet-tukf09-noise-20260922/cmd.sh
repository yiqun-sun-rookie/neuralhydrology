#!/usr/bin/env bash
set -euo pipefail
export PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1

/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python -B - <<'PY'
import base64
import hashlib
import json
from pathlib import Path
import stat

phase = Path('/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/full_budget_integrated_release_20260927_attempt1')
expected = {
    'basin_01047000/run/model/started.json': (1425, 'd2bf2cf6ef1f4ac15a0d58d671d77c79c46462905312861feb610950a703e175'),
    'basin_01047000/run/model/summary.json': (889, 'b0ae827e00f75dc177b8d812cf5e8403316a4dee9beed60d785fab8943f65961'),
    'basin_01047000/run/model/history.npz': (29565, 'a84da227ffee7c12f9a78aa4d75800fbdb202b9304b3ffaca451a86ca058a6f2'),
    'basin_01047000/run/model/manifest.final.sha256.json': (541, '572924fe106a5c0195898f5fc78a94c37bca41f1d897f171deb1cfdd0d131004'),
    'basin_01047000/run/supervisor.json': (192, '1e0d355ebf494e1025672c099a32b0ba2f8339bbd5d1d3640d688137241d4d26'),
    'basin_01047000/control/job_gate.json': (746, '88a2ca6e38df77c35681476272c78b25d8ccf634c1fd61acec268b42538e10f2'),
}
payloads = {}
for relative, (size, digest) in expected.items():
    path = phase / relative
    if not stat.S_ISREG(path.lstat().st_mode):
        raise RuntimeError('not one regular unlinked file: ' + relative)
    data = path.read_bytes()
    if len(data) != size or hashlib.sha256(data).hexdigest() != digest:
        raise RuntimeError('remote evidence differs from terminal receipt: ' + relative)
    payloads[relative] = data
print('FIRST_BASIN_EXACT_EVIDENCE_BEGIN job=228327 basin=01047000 count=6')
for relative, data in payloads.items():
    print('EVIDENCE ' + json.dumps({
        'path': relative,
        'size_bytes': len(data),
        'sha256': hashlib.sha256(data).hexdigest(),
        'base64': base64.b64encode(data).decode('ascii'),
    }, sort_keys=True, separators=(',', ':')))
print('FIRST_BASIN_EXACT_EVIDENCE_END')
PY
