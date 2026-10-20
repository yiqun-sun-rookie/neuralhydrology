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

ROOT = Path('/data1/home/sunyiq/china_input_completion_hpc_20261015_001/glim_egress_diagnostic_20261020_v2')
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
    assert set(payload) == {'CONTRACT.json', 'diagnose_glim_egress_20261020_v2.py'}
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
             str(ROOT / 'diagnose_glim_egress_20261020_v2.py')],
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
    body = json.dumps(dict(root=str(ROOT), stage='C3_GLIM_EGRESS_DIAG_V2', records=records,
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
