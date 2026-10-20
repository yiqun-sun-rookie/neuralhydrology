#!/bin/bash
set -eo pipefail
umask 077
export PYTHONDONTWRITEBYTECODE=1 CUDA_VISIBLE_DEVICES='' OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1
exec timeout --signal=TERM --kill-after=3s 180s /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'NATIVE_REPAIR'
"""Deploy one exclusive source catalogue probe; no Slurm submission or science reads."""
import base64
import datetime
import hashlib
import json
import os
from pathlib import Path
import resource
import shutil
import subprocess
import time
import zlib

ROOT = Path('/data1/home/sunyiq/china_input_completion_hpc_20261015_001/glim_egress_diagnostic_20261020_v1')
PAYLOAD_B64 = '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'
START = time.monotonic()
OWNED = False
ERROR = None


def save(name, value):
    raw = (json.dumps(value, ensure_ascii=False, indent=2) + '\n').encode()
    assert len(raw) <= 524288
    with (ROOT / name).open('xb') as stream:
        stream.write(raw)


def main():
    global OWNED
    resource.setrlimit(resource.RLIMIT_AS, (256 * 1024**2, resource.getrlimit(resource.RLIMIT_AS)[1]))
    assert not ROOT.exists() and ROOT.parent.resolve(strict=True) == ROOT.parent
    assert shutil.disk_usage(ROOT.parent).free >= 64 * 1024**2
    ROOT.mkdir(mode=0o700)
    OWNED = True
    payload = json.loads(zlib.decompress(base64.b64decode(PAYLOAD_B64, validate=True)))
    assert set(payload) == {'CONTRACT.json', 'diagnose_glim_egress_20261020_v1.py'}
    identities = {}
    for name, row in payload.items():
        raw = base64.b64decode(row['base64'], validate=True)
        assert len(raw) == row['bytes'] <= 65536 and hashlib.sha256(raw).hexdigest() == row['sha256']
        with (ROOT / name).open('xb') as stream:
            stream.write(raw)
        assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == row['sha256']
        identities[name] = dict(bytes=len(raw), sha256=row['sha256'])
    contract = json.loads((ROOT / 'CONTRACT.json').read_bytes())
    assert contract['root'] == str(ROOT)
    save('DEPLOYMENT.json', dict(files=identities, slurm_submissions=0))
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE='1',
               CUDA_VISIBLE_DEVICES='', OMP_NUM_THREADS='1', OPENBLAS_NUM_THREADS='1')
    try:
        outcome = subprocess.run(['/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python', '-B',
             str(ROOT / 'diagnose_glim_egress_20261020_v1.py')],
             stdin=subprocess.DEVNULL, capture_output=True, env=env, timeout=160)
        assert len(outcome.stdout) <= 65536 and len(outcome.stderr) <= 65536
        save('PROCESS_RESULT.json', dict(exit_code=outcome.returncode, stdout_bytes=len(outcome.stdout),
             stderr_bytes=len(outcome.stderr), raw_process_output_saved=False, seconds=time.monotonic() - START))
    except subprocess.TimeoutExpired:
        save('PROCESS_RESULT.json', dict(status='PROCESS_TIMEOUT', exit_code=None, seconds=time.monotonic() - START))
    assert sum(p.stat().st_size for p in ROOT.iterdir() if p.is_file()) <= 4 * 1024**2


def frame():
    records = {}
    names = ['DEPLOYMENT.json', 'PROCESS_RESULT.json', 'PROXY_CONFIGURATION.json', 'CONNECTION_PHASES.json', 'NETWORK_STAGE_RESULT.json', 'NETWORK_STAGE_FAILURE.json']
    for name in names:
        path = ROOT / name
        if not OWNED or not path.is_file():
            records[name] = dict(present=False)
            continue
        raw = path.read_bytes()
        assert len(raw) <= 524288
        records[name] = dict(present=True, bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest(),
                             base64=base64.b64encode(raw).decode())
    body = json.dumps(dict(root=str(ROOT), stage='C3_GLIM_EGRESS_DIAG_V1', records=records,
        server_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(), root_created=OWNED,
        error_type=ERROR, slurm_submissions=0, model_calls=0, pixel_values_read=0,
        automatic_checks_enabled=False), separators=(',', ':')).encode()
    assert len(body) <= 4 * 1024**2
    print('NATIVE_REPAIR_BYTES=' + str(len(body)))
    print('NATIVE_REPAIR_SHA256=' + hashlib.sha256(body).hexdigest())
    print('NATIVE_REPAIR_ZLIB_BASE64=' + base64.b64encode(zlib.compress(body)).decode())
    print('NATIVE_REPAIR_DONE', flush=True)


if __name__ == '__main__':
    try:
        main()
    except BaseException as error:
        ERROR = type(error).__name__
    frame()

NATIVE_REPAIR
