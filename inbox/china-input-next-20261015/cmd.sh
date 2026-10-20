#!/bin/bash
set -eo pipefail
umask 077
export PYTHONDONTWRITEBYTECODE=1 CUDA_VISIBLE_DEVICES='' OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1
exec timeout --signal=TERM --kill-after=3s 210s /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'R22_SOURCE'
"""Deploy one exclusive source catalogue probe; no Slurm submission or science reads."""
import base64
import datetime
import hashlib
import json
import os
from pathlib import Path
import resource
import subprocess
import time
import zlib

ROOT = Path('/data1/home/sunyiq/china_input_completion_hpc_20261015_001/geology_remaining22_source_inventory_20261020_v2')
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
    ROOT.mkdir(mode=0o700)
    OWNED = True
    payload = json.loads(zlib.decompress(base64.b64decode(PAYLOAD_B64, validate=True)))
    assert set(payload) == {'CONTRACT.json', 'inventory_remaining22_original_sources_20261020_v2.py'}
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
    env = dict(os.environ, PYTHONPATH=contract['gis_path'], PYTHONDONTWRITEBYTECODE='1',
               CUDA_VISIBLE_DEVICES='', OMP_NUM_THREADS='1', OPENBLAS_NUM_THREADS='1')
    try:
        outcome = subprocess.run(['/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python', '-B',
             str(ROOT / 'inventory_remaining22_original_sources_20261020_v2.py')],
             stdin=subprocess.DEVNULL, capture_output=True, env=env, timeout=190)
        assert len(outcome.stdout) <= 65536 and len(outcome.stderr) <= 65536
        save('PROCESS_RESULT.json', dict(exit_code=outcome.returncode, stdout_bytes=len(outcome.stdout),
             stderr_bytes=len(outcome.stderr), raw_process_output_saved=False, seconds=time.monotonic() - START))
    except subprocess.TimeoutExpired:
        save('PROCESS_RESULT.json', dict(status='PROCESS_TIMEOUT', exit_code=None, seconds=time.monotonic() - START))
    assert sum(p.stat().st_size for p in ROOT.iterdir() if p.is_file()) < 4 * 1024**2


def frame():
    records = {}
    names = ['DEPLOYMENT.json', 'PROCESS_RESULT.json', 'SOFTWARE_DISCOVERY.json', 'SOURCES_INDEX.json',
             'FETCH_RECORDS.json', 'INVENTORY_RESULT.json', 'CGMW_PAGE.html', 'BOREALIS_DATASET.json',
             'BOREALIS_EXPORT.json', 'CGMW_PAGE.html.partial', 'BOREALIS_DATASET.json.partial', 'BOREALIS_EXPORT.json.partial']
    for name in names:
        path = ROOT / name
        if not OWNED or not path.is_file():
            records[name] = dict(present=False)
            continue
        raw = path.read_bytes()
        assert len(raw) <= 524288
        records[name] = dict(present=True, bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest(),
                             base64=base64.b64encode(raw).decode())
    body = json.dumps(dict(root=str(ROOT), stage='C3_REMAINING22_SOURCE_INVENTORY_V2', records=records,
        server_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(), root_created=OWNED,
        error_type=ERROR, slurm_submissions=0, model_calls=0, pixel_values_read=0,
        automatic_checks_enabled=False), separators=(',', ':')).encode()
    assert len(body) <= 4 * 1024**2
    print('R22_SOURCE_BYTES=' + str(len(body)))
    print('R22_SOURCE_SHA256=' + hashlib.sha256(body).hexdigest())
    print('R22_SOURCE_ZLIB_BASE64=' + base64.b64encode(zlib.compress(body)).decode())
    print('R22_SOURCE_DONE', flush=True)


if __name__ == '__main__':
    try:
        main()
    except BaseException as error:
        ERROR = type(error).__name__
    frame()

R22_SOURCE
