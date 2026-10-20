#!/bin/bash
set -eo pipefail
umask 077
export PYTHONDONTWRITEBYTECODE=1 CUDA_VISIBLE_DEVICES='' OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1
exec timeout --signal=TERM --kill-after=3s 2850s /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'NATIVE_REPAIR'
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

ROOT = Path('/data1/home/sunyiq/china_input_completion_hpc_20261015_001/glim_pinned_dns_transfer_20261020_v1')
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
    assert set(payload) == {'CONTRACT.json', 'ROUTES.json', 'transfer_glim_pinned_dns_20261020_v1.py'}
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
             str(ROOT / 'transfer_glim_pinned_dns_20261020_v1.py')],
             stdin=subprocess.DEVNULL, capture_output=True, env=env, timeout=2830)
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
    body = json.dumps(dict(root=str(ROOT), stage='C3_GLIM_PINNED_DNS_V1', records=records,
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
