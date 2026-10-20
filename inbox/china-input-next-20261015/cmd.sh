#!/bin/bash
set -eo pipefail
umask 077
export PYTHONDONTWRITEBYTECODE=1 CUDA_VISIBLE_DEVICES='' OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1
exec timeout --signal=TERM --kill-after=3s 2880s /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'NATIVE_REPAIR'
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

ROOT = Path('/data1/home/sunyiq/china_input_completion_hpc_20261015_001/glim_official_cdn_transfer_20261020_v1')
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
    assert shutil.disk_usage(ROOT.parent).free >= 3 * 1024**3
    ROOT.mkdir(mode=0o700)
    OWNED = True
    payload = json.loads(zlib.decompress(base64.b64decode(PAYLOAD_B64, validate=True)))
    assert set(payload) == {'CONTRACT.json', 'ROUTES.json', 'transfer_glim_official_cdn_20261020_v1.py'}
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
             str(ROOT / 'transfer_glim_official_cdn_20261020_v1.py')],
             stdin=subprocess.DEVNULL, capture_output=True, env=env, timeout=2860)
        assert len(outcome.stdout) <= 65536 and len(outcome.stderr) <= 65536
        save('PROCESS_RESULT.json', dict(exit_code=outcome.returncode, stdout_bytes=len(outcome.stdout),
             stderr_bytes=len(outcome.stderr), raw_process_output_saved=False, seconds=time.monotonic() - START))
    except subprocess.TimeoutExpired:
        save('PROCESS_RESULT.json', dict(status='PROCESS_TIMEOUT', exit_code=None, seconds=time.monotonic() - START))
    assert sum(p.stat().st_size for p in ROOT.iterdir() if p.is_file()) <= 4 * 1024**3 + 4 * 1024**2


def frame():
    records = {}
    names = ['DEPLOYMENT.json', 'PROCESS_RESULT.json', 'NETWORK_REPAIR.json', 'GLIM_TRANSFER.json', 'GLIM_FINAL_GATE.json', 'NETWORK_STAGE_RESULT.json', 'NETWORK_STAGE_FAILURE.json']
    for name in names:
        path = ROOT / name
        if not OWNED or not path.is_file():
            records[name] = dict(present=False)
            continue
        raw = path.read_bytes()
        assert len(raw) <= 524288
        records[name] = dict(present=True, bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest(),
                             base64=base64.b64encode(raw).decode())
    body = json.dumps(dict(root=str(ROOT), stage='C3_GLIM_OFFICIAL_CDN_V1', records=records,
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
