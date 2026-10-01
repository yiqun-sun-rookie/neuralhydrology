#!/bin/bash
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python -B - <<'PY'
import base64
import hashlib
import io
import json
import os
from pathlib import Path
import stat
import subprocess
import zipfile

ROOT = Path('/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_local_selection_remaining_453_20260930_attempt1/canary11')
EXPECTED = {'file_count': 5580, 'total_bytes': 9579015,
            'tree_sha256': '575a0302224a9bc92b40a86259bf4517cfaab4af76746c579c04d9af1a8397a6'}
MAX_FILES = 6000
MAX_SINGLE = 3 * 1024 * 1024
MAX_TOTAL = 12 * 1024 * 1024
MAX_ARCHIVE = 15 * 1024 * 1024
MAX_DIRECTORIES = 6000
MAX_JSON_BYTES = 22 * 1024 * 1024
for parent in (ROOT, *ROOT.parents):
    if parent.is_symlink():
        raise RuntimeError('Linked evidence root or ancestor is forbidden')
if not ROOT.is_dir() or ROOT.resolve() != ROOT:
    raise RuntimeError('Unexpected isolated evidence root')

records, members, directories = [], [], []
total = 0
for path in sorted(ROOT.rglob('*')):
    rel = path.relative_to(ROOT).as_posix()
    if len(rel.encode('utf-8')) > 1024:
        raise RuntimeError('Evidence path length bound exceeded')
    mode = path.lstat().st_mode
    if stat.S_ISLNK(mode):
        raise RuntimeError('Symlink in evidence: ' + rel)
    if stat.S_ISDIR(mode):
        if len(directories) >= MAX_DIRECTORIES:
            raise RuntimeError('Directory count bound exceeded')
        directories.append(rel)
        continue
    if not stat.S_ISREG(mode):
        raise RuntimeError('Nonregular evidence: ' + rel)
    before = path.stat()
    if before.st_size > MAX_SINGLE or len(records) >= MAX_FILES:
        raise RuntimeError('Bound exceeded before reading: ' + rel)
    fd = os.open(str(path), os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, 'rb') as stream:
        data = stream.read(MAX_SINGLE + 1)
    after = path.stat()
    if len(data) != before.st_size or before.st_size != after.st_size or before.st_mtime_ns != after.st_mtime_ns:
        raise RuntimeError('File changed while reading: ' + rel)
    total += len(data)
    if total > MAX_TOTAL:
        raise RuntimeError('Total evidence bound exceeded')
    digest = hashlib.sha256(data).hexdigest()
    records.append({'path': rel, 'size_bytes': len(data), 'sha256': digest,
                    'source_mtime_ns': before.st_mtime_ns, 'source_mode': stat.S_IMODE(mode)})
    members.append((rel, data))

tree = hashlib.sha256()
for row in records:
    tree.update(row['path'].encode('utf-8') + b'\0' + str(row['size_bytes']).encode('ascii')
                + b'\0' + row['sha256'].encode('ascii') + b'\n')
actual = {'file_count': len(records), 'total_bytes': total, 'tree_sha256': tree.hexdigest()}
if actual != EXPECTED:
    print(json.dumps({'status': 'TERMINAL_TREE_CHANGED_CAPTURE_STOPPED', 'expected': EXPECTED, 'actual': actual}))
    raise RuntimeError('Prior terminal file count, byte count, or digest changed; no archive exported')
buffer = io.BytesIO()
with zipfile.ZipFile(buffer, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
    for rel, data in members:
        info = zipfile.ZipInfo(rel, date_time=(1980, 1, 1, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        info.external_attr = (stat.S_IFREG | 0o600) << 16
        archive.writestr(info, data)
packed = buffer.getvalue()
if len(packed) > MAX_ARCHIVE:
    raise RuntimeError('Archive receipt bound exceeded')

def capture(argv):
    result = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=40, check=False)
    if len(result.stdout) + len(result.stderr) > 128 * 1024:
        raise RuntimeError('Scheduler output bound exceeded')
    return {'argv': argv, 'exit_code': result.returncode,
            'stdout': result.stdout.decode('utf-8', errors='strict'),
            'stderr': result.stderr.decode('utf-8', errors='strict')}

scheduler = capture(['sacct', '-j', '233308', '--noheader', '--parsable2',
    '--format=JobID,JobIDRaw,JobName,State,ExitCode,Elapsed,ElapsedRaw,AllocCPUS,Start,End,Timelimit,NodeList,MaxRSS'])
queue = capture(['squeue', '-h', '-j', '233308', '-o', '%i|%T|%R'])
output = {'capture_kind': 'readonly_raw_terminal_archive', 'job_id': '233308',
    'source_root': str(ROOT), 'expected_terminal_tree': EXPECTED, 'actual_terminal_tree': actual,
    'matches_prior_terminal_tree': actual == EXPECTED,
    'member_manifest': records, 'directories': directories,
    'archive_format': 'zip', 'archive_bytes': len(packed),
    'archive_sha256': hashlib.sha256(packed).hexdigest(),
    'archive_base64': base64.b64encode(packed).decode('ascii'),
    'scheduler_accounting': scheduler, 'post_terminal_queue': queue,
    'remote_output_files_created': 0, 'model_or_test_execution': False,
    'scheduler_mutation': False}
serialized = json.dumps(output, ensure_ascii=True, separators=(',', ':'))
if len(serialized.encode('utf-8')) > MAX_JSON_BYTES:
    raise RuntimeError('Complete archive receipt JSON bound exceeded')
print('RAW_TERMINAL_ARCHIVE_JSON_BEGIN')
print(serialized)
print('RAW_TERMINAL_ARCHIVE_JSON_END')
PY
