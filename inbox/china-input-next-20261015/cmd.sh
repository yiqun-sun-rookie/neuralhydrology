#!/bin/bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
exec timeout --signal=TERM --kill-after=2s 15s /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'DBF_PREFIX_ONLY'
import base64
import datetime
import hashlib
import json
import os
from pathlib import Path
import resource
import signal
import stat
import time

SOURCE = Path('/data1/home/sunyiq/china_input_completion_hpc_20261015_001/hydroatlas_extract_headers_v1/level10/BasinATLAS_v10_lev10.dbf')
EXPECTED_BYTES = 1308016122
PREFIX_BYTES = 31681
START = time.monotonic()
resource.setrlimit(resource.RLIMIT_AS, (128 * 1024**2, 128 * 1024**2))
resource.setrlimit(resource.RLIMIT_CPU, (2, 3))

def deadline(signum, frame):
    raise TimeoutError('DBF_PREFIX_READ_DEADLINE')

signal.signal(signal.SIGALRM, deadline)
signal.alarm(10)
assert SOURCE.resolve(strict=True) == SOURCE
fd = os.open(str(SOURCE), os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
try:
    before = os.fstat(fd)
    assert stat.S_ISREG(before.st_mode) and before.st_size == EXPECTED_BYTES
    blocks, used = [], 0
    while used < PREFIX_BYTES:
        block = os.read(fd, min(8192, PREFIX_BYTES-used))
        if not block:
            break
        blocks.append(block)
        used += len(block)
    raw = b''.join(blocks)
    after = os.fstat(fd)
    stable_fields = ('st_dev', 'st_ino', 'st_size', 'st_mtime_ns', 'st_ctime_ns')
    assert all(getattr(before, k) == getattr(after, k) for k in stable_fields)
    assert len(raw) == PREFIX_BYTES and time.monotonic()-START < 10
    metadata = dict(status='EXISTING_FILE_RAW_PREFIX_ONLY', source_path=str(SOURCE), offset=0,
        read_bytes=len(raw), prefix_sha256=hashlib.sha256(raw).hexdigest(), stable=True,
        before={k:int(getattr(before,k)) for k in stable_fields},
        after={k:int(getattr(after,k)) for k in stable_fields},
        historical_expected_full_file_sha256='0ba90446a5b40de864c2b80f0272ca9de915a090b94622806e9eb31d2e84445c',
        full_file_sha256_recomputed=False, hostname=os.uname().nodename,
        server_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
        elapsed_seconds=time.monotonic()-START, new_slurm_jobs=0, source_writes=0,
        attribute_parsing=0, geometry_processing=0, model_calls=0)
    meta = json.dumps(metadata, separators=(',', ':'), sort_keys=True).encode()
    lines = ['DBF_PREFIX_BYTES=' + str(len(raw)),
        'DBF_PREFIX_SHA256=' + hashlib.sha256(raw).hexdigest(),
        'DBF_PREFIX_BASE64=' + base64.b64encode(raw).decode(),
        'DBF_PREFIX_META_BYTES=' + str(len(meta)),
        'DBF_PREFIX_META_SHA256=' + hashlib.sha256(meta).hexdigest(),
        'DBF_PREFIX_META_BASE64=' + base64.b64encode(meta).decode(),
        'DBF_PREFIX_DONE']
    output = '\n'.join(lines) + '\n'
    assert len(output.encode()) < 65536 and time.monotonic()-START < 10
    print(output, end='', flush=True)
finally:
    os.close(fd)
DBF_PREFIX_ONLY
