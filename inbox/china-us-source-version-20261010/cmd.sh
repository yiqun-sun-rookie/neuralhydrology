#!/bin/bash
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1
timeout --signal=KILL 30 /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -I -B -X utf8 - <<'PY'
import datetime
import hashlib
import json
import os
from pathlib import Path
import stat

TARGET = Path('/data1/home/sunyiq/neuralhydrology/data/Caravan/VERSION')
LIMIT = 4096
record = {
    'schema': 'one_caravan_version_metadata_query_v1',
    'path': str(TARGET),
    'max_bytes': LIMIT,
    'started_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'original_time_series_numeric_reads': 0,
    'original_attribute_numeric_reads': 0,
    'new_compute_jobs': 0,
    'model_calls': 0,
    'server_files_modified': 0,
}

def signature(st):
    return (st.st_dev, st.st_ino, st.st_mode, st.st_nlink,
            st.st_size, st.st_mtime_ns, st.st_ctime_ns)

def ancestors():
    for parent in reversed(TARGET.parents):
        info = parent.lstat()
        if not stat.S_ISDIR(info.st_mode) or stat.S_ISLNK(info.st_mode):
            raise RuntimeError('ancestor_not_literal_directory')
    if str(TARGET.resolve(strict=False)) != str(TARGET):
        raise RuntimeError('resolved_path_differs')

try:
    ancestors()
    try:
        before = TARGET.lstat()
    except FileNotFoundError:
        record['status'] = 'ABSENT_AT_EXACT_PATH_NO_ALTERNATIVE_SEARCH'
    else:
        if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1:
            raise RuntimeError('target_not_single_link_regular_file')
        if not 0 < before.st_size <= LIMIT:
            raise RuntimeError('version_size_outside_limit')
        flags = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK
        handle = os.open(str(TARGET), flags)
        try:
            opened = os.fstat(handle)
            if signature(opened) != signature(before):
                raise RuntimeError('identity_changed_before_read')
            with os.fdopen(handle, 'rb', closefd=False) as stream:
                raw = stream.read(before.st_size)
            after_handle = os.fstat(handle)
            ancestors()
            after_path = TARGET.lstat()
            if len(raw) > LIMIT or len(raw) != before.st_size:
                raise RuntimeError('version_read_size_mismatch')
            if signature(before) != signature(after_handle) or signature(before) != signature(after_path):
                raise RuntimeError('identity_changed_during_read')
            content = raw.decode('utf-8', errors='strict')
            if any(ord(char) < 32 and char not in '\r\n\t' for char in content):
                raise RuntimeError('version_contains_control_character')
            record.update(status='READ_ONLY_VERSION_SNAPSHOT_COMPLETE', bytes=len(raw),
                          sha256=hashlib.sha256(raw).hexdigest(), text=content,
                          signature=list(signature(before)))
        finally:
            os.close(handle)
except Exception as error:
    record.update(status='STOP_NO_RETRY', error_type=type(error).__name__)
    if isinstance(error, RuntimeError):
        record['reason'] = str(error)
record['finished_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
print('VERSION_METADATA_JSON=' + json.dumps(record, ensure_ascii=True, sort_keys=True))
if record['status'] == 'STOP_NO_RETRY':
    raise SystemExit(2)
PY
