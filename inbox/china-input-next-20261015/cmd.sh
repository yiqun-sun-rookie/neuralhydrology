#!/bin/bash
set -eo pipefail
umask 077
export PYTHONDONTWRITEBYTECODE=1 CUDA_VISIBLE_DEVICES=''
exec timeout --signal=TERM --kill-after=3s 30s /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'SDK_LAYOUT'
"""Read only the failed private SDK directory's names/stat metadata; no imports or content."""
import datetime
import json
import os
from pathlib import Path
import stat
import time
import hashlib
import zlib
import base64

ROOT = Path('/data1/home/sunyiq/china_input_completion_hpc_20261015_001/weather_ee_offline_20261020_v1')
START = time.monotonic()
assert ROOT.resolve(strict=True) == ROOT
known = ['deps', 'deps/ee', 'deps/ee/__init__.py', 'deps/bin', 'deps/bin/earthengine',
         'deps/lib', 'deps/lib64', 'deps/lib/python3.11/site-packages/ee/__init__.py',
         'deps/lib64/python3.11/site-packages/ee/__init__.py']
rows = []
def describe(path):
    info = path.lstat()
    assert not stat.S_ISLNK(info.st_mode)
    return dict(path=str(path.relative_to(ROOT)), directory=stat.S_ISDIR(info.st_mode), bytes=info.st_size)
for name in known:
    path = ROOT/name
    try:
        rows.append(dict(present=True, **describe(path)))
    except FileNotFoundError:
        rows.append(dict(path=name, present=False))
tree, pending, visited = [], [(ROOT/'deps', 0)], 0
while pending:
    directory, depth = pending.pop()
    if not directory.is_dir():
        continue
    assert directory.resolve(strict=True) == directory
    with os.scandir(directory) as entries:
        for entry in entries:
            visited += 1
            assert visited <= 4096 and time.monotonic()-START < 15
            path = Path(entry.path)
            row = describe(path)
            if row['directory'] or depth == 0 or path.name in ('__init__.py', 'earthengine'):
                tree.append(row)
            if row['directory'] and depth < 4:
                pending.append((path, depth+1))
result = dict(root=str(ROOT), server_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
    known_paths=rows, tree=tree, visited_entries=visited, depth_max=4, seconds=time.monotonic()-START,
    scientific_values_read=0, credential_content_read=False, package_content_read=False,
    imports_attempted=0, installations=0, new_jobs=0, model_calls=0, automatic_checks_enabled=False)
raw = json.dumps(result,ensure_ascii=False,separators=(',',':')).encode()
assert len(raw) <= 1048576 and time.monotonic()-START < 15
print('SDK_LAYOUT_BYTES='+str(len(raw)))
print('SDK_LAYOUT_SHA256='+hashlib.sha256(raw).hexdigest())
print('SDK_LAYOUT_ZLIB_BASE64='+base64.b64encode(zlib.compress(raw)).decode())
print('SDK_LAYOUT_DONE',flush=True)

SDK_LAYOUT
