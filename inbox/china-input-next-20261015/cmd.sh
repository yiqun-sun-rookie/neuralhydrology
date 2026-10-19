#!/bin/bash
set -eo pipefail
umask 077
export CUDA_VISIBLE_DEVICES='' PYTHONDONTWRITEBYTECODE=1
exec timeout --signal=TERM --kill-after=3s 120s /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'C3_FULL_END'
"""One exact deployment or existing-job metadata snapshot; no scientific calculations on login node."""
import base64
import datetime
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import time
import zlib
ROOT = Path('/data1/home/sunyiq/china_input_completion_hpc_20261015_001/china_full_spatial_20261020_v1')
MODE = 'status'
PACKET_B64 = ''
START = time.monotonic()

def utc():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()

def query(command, timeout=9):
    began = time.monotonic()
    p = subprocess.run(command, stdin=subprocess.DEVNULL, capture_output=True, timeout=timeout)
    assert len(p.stdout) <= 65536 and len(p.stderr) <= 16384
    return dict(command=command, exit_code=p.returncode, stdout=p.stdout.decode(errors='replace'), stderr=p.stderr.decode(errors='replace'), server_utc=utc(), seconds=time.monotonic() - began)

def save(name, value):
    with (ROOT / name).open('x', encoding='utf-8') as f:
        json.dump(value, f, ensure_ascii=False, indent=2)
        f.write('\n')

def main():
    assert MODE == 'status' and ROOT.resolve(strict=True) == ROOT
    job = (ROOT / 'OWN_JOB_ID').read_text().strip()
    assert re.fullmatch('[0-9]+', job)
    assert job == '245398', 'EXACT_EXISTING_JOB_ONLY'
    queries = dict(squeue=query(['squeue', '-h', '-j', job, '-o', '%i|%T|%N|%R|%Z']), sacct=query(['sacct', '-X', '-S', '2026-10-19', '-j', job, '--noheader', '--parsable2', '--format=JobIDRaw,State,ExitCode,NodeList,WorkDir%240,Start,End,Elapsed,AllocCPUS,MaxRSS']), scontrol=query(['scontrol', 'show', 'job', job, '-o']))
    names = ['DEPLOYMENT.json', 'SUBMISSION_STARTED.json', 'SUBMISSION_RESULT.json', 'OWN_JOB_ID', 'CONTROL_STARTED.json', 'CONTROL_RESULT.json', 'CONTROL_FAILURE.json', 'DIFFERENCES.json', 'main_EXIT.json', 'independent_EXIT.json', 'main.stdout', 'main.stderr', 'independent.stdout', 'independent.stderr', 'logs/full-' + job + '.out', 'logs/full-' + job + '.err']
    evidence_indices = {}
    for tag in ('main', 'independent'):
        names += [tag + '/' + name for name in ('STARTED.json', 'GLOBAL.json', 'FAILURE.json')]
        folder = ROOT / tag
        if folder.is_dir():
            progress = sorted(folder.glob('PROGRESS_[0-9][0-9][0-9][0-9].json'))
            if progress:
                names.append(str(progress[-1].relative_to(ROOT)))
            ixprogress = sorted(folder.glob('INDEX_PROGRESS_*.json'))
            if ixprogress:
                names.append(str(ixprogress[-1].relative_to(ROOT)))
            index = folder / 'INDEX.json'
            if index.exists():
                before = index.stat()
                assert before.st_size <= 8 * 1024 ** 2
                raw = index.read_bytes()
                after = index.stat()
                assert (before.st_size, before.st_mtime_ns) == (after.st_size, after.st_mtime_ns)
                value = json.loads(raw)
                workload = value.get('workload', value)
                keys = ('candidate_occurrences', 'candidate_vertices_total', 'index_bytes', 'index_entries', 'seconds', 'peak_rss_kib')
                evidence_indices[tag] = dict(path=str(index), bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest(), workload={k: workload[k] for k in keys if k in workload})
    if (ROOT / 'main/AREA_LOG.json').exists():
        names.append('main/AREA_LOG.json')
    if (ROOT / 'CONTROL_RESULT.json').exists():
        result = json.loads((ROOT / 'CONTROL_RESULT.json').read_bytes())
        names += [x['path'] for x in result['result_indices']]
    assert len(names) == len(set(names))
    records, total = ({}, 0)
    for name in names:
        path = ROOT / name
        if not path.exists():
            records[name] = dict(present=False)
            continue
        assert path.resolve(strict=True) == path and path.is_file() and (not path.is_symlink())
        before = path.stat()
        assert before.st_size <= 1048576
        raw = path.read_bytes()
        after = path.stat()
        assert (before.st_size, before.st_mtime_ns) == (after.st_size, after.st_mtime_ns) and len(raw) == before.st_size
        total += len(raw)
        assert total <= 16 * 1024 ** 2
        records[name] = dict(present=True, bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest(), base64=base64.b64encode(raw).decode())
    value = dict(root=str(ROOT), job_id=job, mode=MODE, server_utc=utc(), queries=queries, records=records, evidence_indices=evidence_indices, seconds=time.monotonic() - START, model_calls=0, automatic_checks_enabled=False)
    raw = json.dumps(value, ensure_ascii=False, separators=(',', ':')).encode()
    assert len(raw) < 24 * 1024 ** 2
    print('FULL_STATUS_BYTES=' + str(len(raw)))
    print('FULL_STATUS_SHA256=' + hashlib.sha256(raw).hexdigest())
    print('FULL_STATUS_ZLIB_BASE64=' + base64.b64encode(zlib.compress(raw)).decode())
    print('FULL_STATUS_DONE', flush=True)
if __name__ == '__main__':
    main()

C3_FULL_END
