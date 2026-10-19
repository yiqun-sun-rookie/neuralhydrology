#!/bin/bash
set -eo pipefail
umask 077
export PYTHONDONTWRITEBYTECODE=1
exec timeout --signal=TERM --kill-after=5s 45s /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY_EXISTING_244015'
"""One bounded read-only inspection of the existing job, never a submission."""
import base64
import datetime
import hashlib
import json
import os
from pathlib import Path
import signal
import stat
import subprocess
import time
import zlib

ROOT = Path('/data1/home/sunyiq/china_input_completion_hpc_20261015_001/hydroatlas_extract_headers_v1')
JOB = '244015'
START = time.monotonic()
READ_LIMIT = 2 * 1024**2
used = 0


def utc():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def deadline(signum, frame):
    raise TimeoutError('READ_ONLY_STATUS_DEADLINE')


def small_file(name, maximum=65536, tail=False):
    global used
    path = ROOT / name
    answer = dict(path=str(path), present=False)
    try:
        assert path.resolve(strict=True) == path
        fd = os.open(str(path), os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except FileNotFoundError:
        return answer
    except Exception as error:
        return dict(answer, error=type(error).__name__ + ':' + str(error))
    try:
        before = os.fstat(fd)
        assert stat.S_ISREG(before.st_mode)
        answer.update(present=True, file_bytes=before.st_size)
        count = min(before.st_size, maximum)
        if before.st_size > maximum and not tail:
            return dict(answer, error='SMALL_RECORD_TOO_LARGE', complete=False)
        assert used + count <= READ_LIMIT
        offset = max(0, before.st_size - count) if tail else 0
        os.lseek(fd, offset, os.SEEK_SET)
        blocks, remaining = [], count
        while remaining:
            block = os.read(fd, min(8192, remaining))
            if not block:
                break
            blocks.append(block)
            used += len(block)
            remaining -= len(block)
            assert used <= READ_LIMIT
        raw = b''.join(blocks)
        after = os.fstat(fd)
        stable = (before.st_ino, before.st_size, before.st_mtime_ns) == (
            after.st_ino, after.st_size, after.st_mtime_ns)
        complete = stable and offset == 0 and len(raw) == before.st_size
        answer.update(read_bytes=len(raw), offset=offset, stable=stable, complete=complete,
                      snapshot_sha256=hashlib.sha256(raw).hexdigest(),
                      snapshot_base64=base64.b64encode(raw).decode())
        return answer
    finally:
        os.close(fd)


def query(command):
    import selectors
    began = time.monotonic()
    result = dict(command=command, server_started_utc=utc(), exit_code=None,
                  within_deadline=False, complete_output=False)
    buffers = {'stdout': bytearray(), 'stderr': bytearray()}
    process = None
    try:
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   stdin=subprocess.DEVNULL, start_new_session=True)
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ, 'stdout')
            selector.register(process.stderr, selectors.EVENT_READ, 'stderr')
            while selector.get_map():
                assert time.monotonic() - began < 9 and time.monotonic() - START < 35
                for key, _ in selector.select(.1):
                    block = os.read(key.fileobj.fileno(), 4096)
                    if not block:
                        selector.unregister(key.fileobj)
                    else:
                        maximum = 65536 if key.data == 'stdout' else 8192
                        assert len(buffers[key.data]) + len(block) <= maximum
                        buffers[key.data].extend(block)
            remaining = 9 - (time.monotonic() - began)
            assert remaining > 0
            result['exit_code'] = process.wait(timeout=remaining)
            result['exit_observed_elapsed_seconds'] = time.monotonic() - began
            result['within_deadline'] = result['exit_observed_elapsed_seconds'] <= 9
            result['complete_output'] = True
    except BaseException as error:
        if process is not None:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait(timeout=2)
            result['process_returncode_after_cleanup'] = process.returncode
        result.update(error=type(error).__name__ + ':' + str(error))
        if not isinstance(error, Exception):
            raise
    finally:
        if process is not None:
            for stream in (process.stdout, process.stderr):
                if stream is not None:
                    stream.close()
    result.update(server_finished_utc=utc(), elapsed_seconds=time.monotonic() - began,
                  **{k: bytes(v).decode(errors='replace') for k, v in buffers.items()})
    return result


def main():
    signal.signal(signal.SIGALRM, deadline)
    signal.alarm(40)
    assert ROOT.resolve(strict=True) == ROOT and ROOT.is_dir()
    proof = small_file('OWN_EXTRACT_JOB_ID', 32)
    assert proof.get('complete') and base64.b64decode(proof['snapshot_base64']) == b'244015\n'
    commands = {
        'squeue': ['squeue', '-h', '-j', JOB, '-o', '%i|%T|%N|%R|%Z'],
        'sacct': ['sacct', '-X', '-S', '2026-10-16', '-j', JOB, '--noheader', '--parsable2',
                  '--format=JobIDRaw,State,ExitCode,NodeList,WorkDir%240,Start,End,Elapsed,AllocCPUS'],
        'scontrol': ['scontrol', 'show', 'job', JOB, '-o'],
    }
    queries = {name: query(command) for name, command in commands.items()}
    names = ['SUBMISSION_STARTED.json', 'SUBMISSION_RESULT.json', 'IMMEDIATE_JOB_STATE.json',
             'DEPLOYMENT_STARTED.json', 'CONTROL_STARTED.json', 'CONTROL_RESULT.json', 'CONTROL_FAILURE.json',
             'HYDROATLAS_ACQUISITION_RESULT.json', 'HYDROATLAS_ACQUISITION_FAILURE.json',
             'EXTRACT_PARTIAL_IDENTITIES.json', 'HYDROATLAS_LEVEL10_HEADERS.json']
    names += [stage + suffix for stage in ('extract', 'headers')
              for suffix in ('_LAUNCH.json', '_STAGE_RESULT.json', '_STAGE_POSTWRITE.json')]
    records = {name: small_file(name, 131072 if name == 'HYDROATLAS_LEVEL10_HEADERS.json' else 65536)
               for name in names}
    records['OWN_EXTRACT_JOB_ID'] = proof
    for name in ['extract.stdout', 'extract.stderr', 'headers.stdout', 'headers.stderr',
                 'logs/source-244015.out', 'logs/source-244015.err']:
        records[name] = small_file(name, 16384, tail=True)
    members = {}
    for suffix in ('dbf', 'prj', 'shp', 'shx'):
        path = ROOT / 'level10' / ('BasinATLAS_v10_lev10.' + suffix)
        try:
            assert path.resolve(strict=True) == path
            info = path.stat()
            assert stat.S_ISREG(info.st_mode)
            members[str(path)] = dict(bytes=info.st_size, mtime_ns=info.st_mtime_ns, body_read_bytes=0)
        except FileNotFoundError:
            members[str(path)] = dict(present=False, body_read_bytes=0)
    result = dict(job_id=JOB, remote_root=str(ROOT), server_finished_utc=utc(), hostname=os.uname().nodename,
                  queries=queries, records=records, extracted_member_stats=members,
                  metadata_bytes_read=used, elapsed_seconds=time.monotonic() - START,
                  new_submissions=0, cancellations=0, source_gets=0, scientific_feature_value_reads=0,
                  scientific_array_reads=0, model_calls=0, automatic_checks_enabled=False,
                  input_admission_approved=False, prediction_approved=False)
    raw = json.dumps(result, ensure_ascii=False, separators=(',', ':'), allow_nan=False).encode()
    assert len(raw) <= 3 * 1024**2 and time.monotonic() - START < 40
    packed = zlib.compress(raw)
    print('OWN_244015_STATUS_BYTES=' + str(len(raw)))
    print('OWN_244015_STATUS_SHA256=' + hashlib.sha256(raw).hexdigest())
    print('OWN_244015_STATUS_ZLIB_BASE64=' + base64.b64encode(packed).decode())
    print('OWN_244015_STATUS_DONE', flush=True)


if __name__ == '__main__':
    main()

PY_EXISTING_244015
