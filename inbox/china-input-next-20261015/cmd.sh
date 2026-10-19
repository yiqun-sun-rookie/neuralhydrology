#!/bin/bash
set -eo pipefail
umask 077
export CUDA_VISIBLE_DEVICES='' PYTHONDONTWRITEBYTECODE=1
exec timeout --signal=TERM --kill-after=3s 120s /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'C3_SPATIAL_BRIDGE'
"""Metadata-only deployment/submission/status transport for one isolated pilot."""
import base64
import datetime
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import time
import traceback
import zlib

ROOT = Path('/data1/home/sunyiq/china_input_completion_hpc_20261015_001/china_four_fields_spatial_20261019_v1')
MODE = 'status'
PACKET_B64 = ''
START = time.monotonic()


def utc():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def save(name, value):
    with (ROOT / name).open('x', encoding='utf-8') as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write('\n')


def query(command, timeout=9):
    began = time.monotonic()
    p = subprocess.run(command, stdin=subprocess.DEVNULL, capture_output=True, timeout=timeout)
    assert len(p.stdout) <= 65536 and len(p.stderr) <= 16384
    return dict(command=command, exit_code=p.returncode, stdout=p.stdout.decode(errors='replace'),
                stderr=p.stderr.decode(errors='replace'), server_utc=utc(), seconds=time.monotonic() - began)


def main():
    if MODE == 'deploy':
        assert not ROOT.exists(), 'ROOT_ALREADY_EXISTS_DO_NOT_RESUBMIT'
        prior = query(['sacct', '-X', '-S', '2026-10-19', '-j', '245247', '--noheader', '--parsable2',
                       '--format=JobIDRaw,State,ExitCode'])
        assert prior['exit_code'] == 0 and ['245247', 'COMPLETED', '0:0'] in [
            line.strip().split('|') for line in prior['stdout'].splitlines() if line.strip()]
        packet = json.loads(zlib.decompress(base64.b64decode(PACKET_B64, validate=True)))
        assert set(packet) == {'CONTRACT.json', 'c3_spatial_main_20261019_v1.py',
            'c3_spatial_independent_20261019_v2.py', 'c3_spatial_control_20261019_v2.py', 'c3_spatial_20261019_v2.sbatch'}
        ROOT.mkdir()
        (ROOT / 'logs').mkdir()
        assert shutil.disk_usage(ROOT).free >= 3 * 1024**3
        deployed = {}
        for name, member in sorted(packet.items()):
            raw = base64.b64decode(member['base64'], validate=True)
            assert len(raw) == member['bytes'] < 131072 and hashlib.sha256(raw).hexdigest() == member['sha256']
            assert b'\r' not in raw
            with (ROOT / name).open('xb') as stream:
                stream.write(raw)
            assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == member['sha256']
            deployed[name] = member['sha256']
        save('DEPLOYMENT.json', dict(files=deployed, prior_job=prior, server_utc=utc()))
        save('SUBMISSION_STARTED.json', dict(max_new_jobs=1, automatic_retries=0, server_utc=utc()))
        result = query(['sbatch', str(ROOT / 'c3_spatial_20261019_v2.sbatch')], timeout=15)
        save('SUBMISSION_RESULT.json', result)
        found = re.findall(r'^Submitted batch job ([0-9]+)\s*$', result['stdout'], re.M)
        assert result['exit_code'] == 0 and len(found) == 1, 'NO_CONFIRMED_JOB_NO_RETRY'
        job = found[0]
        with (ROOT / 'OWN_JOB_ID').open('x') as stream:
            stream.write(job + '\n')
    else:
        assert MODE == 'status' and ROOT.resolve(strict=True) == ROOT
        job = (ROOT / 'OWN_JOB_ID').read_text().strip()
    assert re.fullmatch(r'[0-9]+', job)
    queries = {
        'squeue': query(['squeue', '-h', '-j', job, '-o', '%i|%T|%N|%R|%Z']),
        'sacct': query(['sacct', '-X', '-S', '2026-10-19', '-j', job, '--noheader', '--parsable2',
                       '--format=JobIDRaw,State,ExitCode,NodeList,WorkDir%240,Start,End,Elapsed,AllocCPUS,MaxRSS']),
        'scontrol': query(['scontrol', 'show', 'job', job, '-o'])}
    contract = json.loads((ROOT / 'CONTRACT.json').read_bytes())
    names = ['DEPLOYMENT.json', 'SUBMISSION_STARTED.json', 'SUBMISSION_RESULT.json', 'OWN_JOB_ID',
             'CONTROL_STARTED.json', 'CONTROL_RESULT.json', 'CONTROL_FAILURE.json',
             'main_EXIT.json', 'independent_EXIT.json', 'main.stdout', 'main.stderr',
             'independent.stdout', 'independent.stderr', 'logs/pilot-' + job + '.out', 'logs/pilot-' + job + '.err']
    for tag in ('main', 'independent'):
        names += [tag + '/' + name for name in ('STARTED.json', 'GLOBAL.json', 'FAILURE.json')]
        names += [tag + '/member_' + item['basin_id'] + '.json' for item in contract['selected_targets']]
        if (ROOT / tag).is_dir():
            progress = sorted((ROOT / tag).glob('PROGRESS*.json'))
            assert len(progress) <= 20
            names += [str(path.relative_to(ROOT)) for path in progress]
    assert len(names) == len(set(names))
    records, total = {}, 0
    for name in names:
        path = ROOT / name
        if not path.exists():
            records[name] = dict(present=False)
            continue
        assert path.resolve(strict=True) == path and path.is_file()
        before = path.stat()
        assert before.st_size <= 1048576
        raw = path.read_bytes()
        after = path.stat()
        assert (before.st_size, before.st_mtime_ns) == (after.st_size, after.st_mtime_ns) and len(raw) == before.st_size
        total += len(raw)
        assert total <= 16 * 1024**2
        records[name] = dict(present=True, bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest(),
                             base64=base64.b64encode(raw).decode())
    value = dict(job_id=job, root=str(ROOT), mode=MODE, server_utc=utc(), queries=queries, records=records,
                 seconds=time.monotonic() - START, model_calls=0, automatic_checks_enabled=False)
    raw = json.dumps(value, ensure_ascii=False, separators=(',', ':')).encode()
    assert len(raw) < 24 * 1024**2
    print('PILOT_STATUS_BYTES=' + str(len(raw)))
    print('PILOT_STATUS_SHA256=' + hashlib.sha256(raw).hexdigest())
    print('PILOT_STATUS_ZLIB_BASE64=' + base64.b64encode(zlib.compress(raw)).decode())
    print('PILOT_STATUS_DONE', flush=True)


if __name__ == '__main__':
    try:
        main()
    except BaseException:
        traceback.print_exc()
        raise

C3_SPATIAL_BRIDGE
