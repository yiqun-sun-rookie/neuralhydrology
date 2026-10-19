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
MODE = 'deploy'
PACKET_B64 = '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'
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
