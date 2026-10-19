#!/bin/bash
set -eo pipefail
umask 077
export PYTHONDONTWRITEBYTECODE=1
exec timeout --signal=TERM --kill-after=3s 60s /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'DBF_BOUND_CONTROL'
"""Login-node transport, one submission, and bounded job/report reads only."""
import base64
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time
import traceback
import zlib

ROOT = Path('/data1/home/sunyiq/china_input_completion_hpc_20261015_001/dbf_tokens_20261019_v1')
MODE = 'status'
PACKET_B64 = ''
START = time.monotonic()


def utc():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def save(name, value):
    with (ROOT / name).open('x', encoding='utf-8') as handle:
        json.dump(value, handle, ensure_ascii=False, indent=2)
        handle.write('\n')


def query(cmd, timeout=9):
    began = time.monotonic()
    result = subprocess.run(cmd, capture_output=True, stdin=subprocess.DEVNULL, timeout=timeout)
    assert len(result.stdout) <= 65536 and len(result.stderr) <= 16384
    return dict(command=cmd, exit_code=result.returncode, stdout=result.stdout.decode(errors='replace'),
                stderr=result.stderr.decode(errors='replace'), server_utc=utc(), seconds=time.monotonic()-began)


def main():
    if MODE == 'deploy':
        assert not ROOT.exists(), 'EXCLUSIVE_ROOT_ALREADY_EXISTS_NO_REPLAY'
        prior = query(['sacct', '-X', '-S', '2026-10-16', '-j', '244015', '--noheader', '--parsable2',
                       '--format=JobIDRaw,State,ExitCode,WorkDir%240'])
        expected = '/data1/home/sunyiq/china_input_completion_hpc_20261015_001/hydroatlas_extract_headers_v1'
        rows = [row.strip().split('|') for row in prior['stdout'].splitlines() if row.strip()]
        assert prior['exit_code'] == 0 and any(row[:4] == ['244015', 'COMPLETED', '0:0', expected] for row in rows)
        packet = json.loads(zlib.decompress(base64.b64decode(PACKET_B64, validate=True)))
        allowed = {'dbf_tokens_primary_20261019_v1.py', 'independent_dbf_tokens_20261019_v1.py',
                   'dbf_tokens_control_20261019_v1.py', 'dbf_tokens_20261019_v1.sbatch'}
        assert set(packet) == allowed
        ROOT.mkdir()
        (ROOT / 'logs').mkdir()
        hashes = {}
        for name in sorted(allowed):
            raw = base64.b64decode(packet[name]['base64'], validate=True)
            assert len(raw) == packet[name]['bytes'] < 65536
            assert hashlib.sha256(raw).hexdigest() == packet[name]['sha256'] and b'\r' not in raw
            with (ROOT / name).open('xb') as handle:
                handle.write(raw)
            assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == packet[name]['sha256']
            hashes[name] = packet[name]['sha256']
        save('DEPLOYMENT.json', dict(server_utc=utc(), files=hashes, prior_job=prior))
        save('SUBMISSION_STARTED.json', dict(server_utc=utc(), max_submissions=1, automatic_retry=False))
        submission = query(['sbatch', str(ROOT / 'dbf_tokens_20261019_v1.sbatch')], timeout=15)
        save('SUBMISSION_RESULT.json', submission)
        found = re.findall(r'^Submitted batch job ([0-9]+)\s*$', submission['stdout'], re.M)
        assert submission['exit_code'] == 0 and len(found) == 1, 'NO_CONFIRMED_JOB_DO_NOT_RESUBMIT'
        job = found[0]
        with (ROOT / 'OWN_JOB_ID').open('x') as handle:
            handle.write(job + '\n')
    else:
        assert MODE == 'status' and ROOT.resolve(strict=True) == ROOT
        job = (ROOT / 'OWN_JOB_ID').read_text().strip()
    assert re.fullmatch(r'[0-9]+', job)
    queries = {
        'squeue': query(['squeue', '-h', '-j', job, '-o', '%i|%T|%N|%R|%Z']),
        'sacct': query(['sacct', '-X', '-S', '2026-10-19', '-j', job, '--noheader', '--parsable2',
                        '--format=JobIDRaw,State,ExitCode,NodeList,WorkDir%240,Start,End,Elapsed,AllocCPUS']),
        'scontrol': query(['scontrol', 'show', 'job', job, '-o'])}
    names = ['DEPLOYMENT.json', 'SUBMISSION_STARTED.json', 'SUBMISSION_RESULT.json', 'OWN_JOB_ID',
             'CONTROL_STARTED.json', 'CONTROL_RESULT.json', 'CONTROL_FAILURE.json',
             'PRIMARY_STARTED.json', 'PRIMARY_RESULT.json', 'PRIMARY_FAILURE.json', 'PRIMARY_EXIT.json',
             'INDEPENDENT_STARTED.json', 'INDEPENDENT_RESULT.json', 'INDEPENDENT_FAILURE.json', 'INDEPENDENT_EXIT.json',
             'PRIMARY.stdout', 'PRIMARY.stderr', 'INDEPENDENT.stdout', 'INDEPENDENT.stderr',
             'logs/dbf-' + job + '.out', 'logs/dbf-' + job + '.err']
    records = {}
    for name in names:
        path = ROOT / name
        if not path.exists():
            records[name] = dict(present=False)
            continue
        assert path.resolve(strict=True) == path and path.is_file()
        before = path.stat()
        assert before.st_size <= 262144
        raw = path.read_bytes()
        after = path.stat()
        assert (before.st_size, before.st_mtime_ns) == (after.st_size, after.st_mtime_ns) and len(raw) == before.st_size
        records[name] = dict(present=True, bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest(),
                             base64=base64.b64encode(raw).decode())
    result = dict(job_id=job, root=str(ROOT), mode=MODE, server_utc=utc(), queries=queries,
                  records=records, seconds=time.monotonic()-START, model_calls=0, automatic_checks_enabled=False)
    raw = json.dumps(result, separators=(',', ':'), ensure_ascii=False).encode()
    assert len(raw) < 2*1024**2
    print('DBF_STATUS_BYTES=' + str(len(raw)))
    print('DBF_STATUS_SHA256=' + hashlib.sha256(raw).hexdigest())
    print('DBF_STATUS_ZLIB_BASE64=' + base64.b64encode(zlib.compress(raw)).decode())
    print('DBF_STATUS_DONE', flush=True)


if __name__ == '__main__':
    try:
        main()
    except BaseException:
        traceback.print_exc()
        raise

DBF_BOUND_CONTROL
