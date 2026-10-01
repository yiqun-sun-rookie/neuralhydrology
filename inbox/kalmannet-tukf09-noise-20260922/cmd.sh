#!/bin/bash
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python -B - <<'PY'
import hashlib
import json
import os
from pathlib import Path
import stat

ROOT = Path('/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/full_budget_01142500_20260928_attempt1/bundle')
EXPECTED_MANIFEST = '4ebee2dcbd215e9751c86ca9895b84090956e7857d84b524fc87d60a3ea6afa1'
MAX_READ_TOTAL = 128 * 1024 * 1024
read_total = 0

def read_bounded(path, single_limit):
    global read_total
    allowed = min(single_limit, MAX_READ_TOTAL - read_total - 1)
    if allowed < 0:
        raise RuntimeError('Actual total read budget exhausted')
    fd = os.open(str(path), os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, 'rb') as stream:
        before = os.fstat(stream.fileno())
        if not stat.S_ISREG(before.st_mode) or before.st_size > allowed:
            raise RuntimeError('Opened file type or size exceeds bound')
        data = stream.read(allowed + 1)
        read_total += len(data)
        after = os.fstat(stream.fileno())
    current = path.lstat()
    if len(data) > allowed or len(data) != before.st_size or before.st_size != after.st_size:
        raise RuntimeError('File changed or read bound exceeded')
    if before.st_mtime_ns != after.st_mtime_ns or (before.st_dev, before.st_ino) != (current.st_dev, current.st_ino):
        raise RuntimeError('File identity or modification time changed')
    return data, before
for parent in (ROOT, *ROOT.parents):
    if parent.is_symlink():
        raise RuntimeError('Linked frozen parent root forbidden')
if ROOT.resolve() != ROOT or not ROOT.is_dir():
    raise RuntimeError('Unexpected frozen parent root')
manifest_path = ROOT / 'bundle_manifest.json'
if manifest_path.is_symlink() or not manifest_path.is_file() or manifest_path.stat().st_size > 1024 * 1024:
    raise RuntimeError('Invalid parent manifest')
manifest_bytes, _ = read_bounded(manifest_path, 1024 * 1024)
if hashlib.sha256(manifest_bytes).hexdigest() != EXPECTED_MANIFEST:
    raise RuntimeError('Frozen parent manifest changed')
manifest = json.loads(manifest_bytes)
registered = manifest['files']
if not isinstance(registered, dict) or len(registered) != 325:
    raise RuntimeError('Unexpected frozen parent member inventory')
records = []
unknown_not_read = []
total = 0
for path in sorted(ROOT.rglob('*')):
    relative = path.relative_to(ROOT).as_posix()
    if len(relative.encode('utf-8')) > 1024:
        raise RuntimeError('Path bound exceeded')
    mode = path.lstat().st_mode
    if stat.S_ISLNK(mode):
        raise RuntimeError('Parent linked member forbidden')
    if stat.S_ISDIR(mode):
        continue
    if not stat.S_ISREG(mode) or len(records) >= 1000:
        raise RuntimeError('Parent member type or count bound exceeded')
    before = path.stat()
    total += before.st_size
    if before.st_size > 32 * 1024 * 1024 or total > 128 * 1024 * 1024:
        raise RuntimeError('Parent size bound exceeded')
    if relative not in registered and relative != 'bundle_manifest.json' and not relative.endswith('.pyc'):
        row = {'path': relative, 'size_bytes': before.st_size, 'sha256': None,
               'source_mtime_ns': before.st_mtime_ns, 'content_read': False}
        unknown_not_read.append(row)
        records.append(row)
        continue
    data, opened = read_bounded(path, 32 * 1024 * 1024)
    after = path.stat()
    if len(data) != before.st_size or before.st_size != after.st_size or before.st_mtime_ns != after.st_mtime_ns or (opened.st_dev, opened.st_ino) != (before.st_dev, before.st_ino):
        raise RuntimeError('Parent evidence changed while reading')
    digest = hashlib.sha256(data).hexdigest()
    if relative in registered and (digest != registered[relative]['sha256'] or len(data) != registered[relative]['size_bytes']):
        raise RuntimeError('Registered frozen parent member changed: ' + relative)
    records.append({'path': relative, 'size_bytes': len(data),
                    'sha256': digest, 'source_mtime_ns': before.st_mtime_ns, 'content_read': True})
if not set(registered).issubset({row['path'] for row in records}):
    raise RuntimeError('Registered frozen parent member missing')
report = {'capture_kind': 'readonly_frozen_parent_inventory', 'source_root': str(ROOT),
          'bundle_manifest_sha256': EXPECTED_MANIFEST, 'file_count': len(records),
          'total_bytes': total, 'file_inventory': records,
          'actual_read_bytes_including_repeated_manifest': read_total,
          'manifest_member_schema': list(manifest),
          'bytecode_files': [row for row in records if row['path'].endswith('.pyc')],
          'registered_members_verified': len(registered),
          'unregistered_nonbytecode_files_not_read': unknown_not_read,
          'model_or_test_execution': False, 'scheduler_mutation': False, 'remote_output_files_created': 0}
serialized = json.dumps(report, ensure_ascii=True, separators=(',', ':'))
if len(serialized.encode('utf-8')) > 1024 * 1024:
    raise RuntimeError('Inventory output bound exceeded')
print('PARENT_INVENTORY_JSON_BEGIN')
print(serialized)
print('PARENT_INVENTORY_JSON_END')
PY
