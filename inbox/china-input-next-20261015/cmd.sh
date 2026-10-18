#!/bin/bash
set -eo pipefail
umask 077
export PYTHONDONTWRITEBYTECODE=1
exec timeout --signal=TERM --kill-after=5s 90s /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY_OWN_RESOURCES'
"""Bounded own-user Slurm resource/configuration inspection; no submissions or scientific reads."""
import base64
import datetime
import hashlib
import json
import os
import pwd
import re
import selectors
import signal
import subprocess
import time
import zlib

START = time.monotonic()
USER = pwd.getpwuid(os.getuid()).pw_name
RESULTS = {}


def utc():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def interrupted(signum, frame):
    raise TimeoutError('OWN_RESOURCE_METADATA_DEADLINE')


def query(label, command):
    assert label not in RESULTS and len(RESULTS) < 12 and time.monotonic() - START < 75
    began = time.monotonic()
    result = dict(command=command, server_started_utc=utc(), exit_code=None,
                  complete_output=False, within_deadline=False)
    process = None
    buffers = {'stdout': bytearray(), 'stderr': bytearray()}
    try:
        process = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, start_new_session=True)
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ, 'stdout')
            selector.register(process.stderr, selectors.EVENT_READ, 'stderr')
            while selector.get_map():
                assert time.monotonic() - began < 6 and time.monotonic() - START < 80
                for key, _ in selector.select(.1):
                    block = os.read(key.fileobj.fileno(), 4096)
                    if not block:
                        selector.unregister(key.fileobj)
                    else:
                        assert len(buffers[key.data]) + len(block) <= (65536 if key.data == 'stdout' else 8192)
                        buffers[key.data].extend(block)
            remaining = 6 - (time.monotonic() - began)
            assert remaining > 0
            result['exit_code'] = process.wait(timeout=remaining)
            result['exit_observed_elapsed_seconds'] = time.monotonic() - began
            result['complete_output'] = True
            result['within_deadline'] = result['exit_observed_elapsed_seconds'] <= 6
    except BaseException as error:
        if process is not None:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait(timeout=2)
            result['process_returncode_after_cleanup'] = process.returncode
        result['error'] = type(error).__name__ + ':' + str(error)
        if not isinstance(error, Exception):
            raise
    finally:
        if process is not None:
            for stream in (process.stdout, process.stderr):
                if stream is not None:
                    stream.close()
    result.update(server_finished_utc=utc(), elapsed_seconds=time.monotonic() - began,
                  **{name: bytes(value).decode(errors='replace') for name, value in buffers.items()})
    RESULTS[label] = result
    return result


def good(result):
    return result['exit_code'] == 0 and result['complete_output'] and result['within_deadline']


def names(value):
    result = set()
    for item in value.split(','):
        part = item.strip().lstrip('+-')
        if (part.lower() not in ('none', 'n/a', '(null)', 'all', 'unlimited')
                and re.fullmatch(r'[A-Za-z_][A-Za-z0-9_.-]{0,63}', part)):
            result.add(part)
    return result


def main():
    assert USER == 'sunyiq' and os.getuid() == 2272
    signal.signal(signal.SIGALRM, interrupted)
    signal.signal(signal.SIGTERM, interrupted)
    signal.alarm(85)
    began_utc = utc()
    associations = query('own_association_identity', ['sacctmgr', '-n', '-P', 'show', 'assoc', 'where',
        'user=' + USER, 'format=Cluster,Account,User,Partition,QOS%256,DefaultQOS'])
    # Default columns avoid guessing version-specific association limit field aliases.
    query('own_association_visible_limits', ['sacctmgr', '-P', 'show', 'assoc', 'where', 'user=' + USER])
    queue = query('own_visible_jobs', ['squeue', '-h', '-u', USER, '-o',
        '%i|%T|%a|%q|%P|%C|%D|%N|%R|%Z|%l|%L|%v'])
    history = query('historical_244015_accounting', ['sacct', '-X', '-S', '2026-10-16', '-j', '244015',
        '--noheader', '--parsable2',
        '--format=JobIDRaw,User,Account,QOS,Partition,State,ExitCode,ElapsedRaw,AllocCPUS,AllocTRES%512'])
    query('hgpu2p_partition', ['scontrol', 'show', 'partition', 'hgpu2p', '-o'])
    query('hgpu2p_visible_capacity', ['sinfo', '-h', '-p', 'hgpu2p', '-o', '%P|%a|%l|%D|%C|%G'])
    qos, reservations, own_accounts = set(), set(), set()
    if good(associations):
        for line in associations['stdout'].splitlines():
            row = [part.strip() for part in line.split('|')]
            if len(row) >= 6 and row[2] == USER:
                own_accounts.add(row[1])
                qos |= names(row[4]) | names(row[5])
    if good(queue):
        for line in queue['stdout'].splitlines():
            row = [part.strip() for part in line.split('|')]
            if len(row) >= 13:
                qos |= names(row[3])
                reservations |= names(row[12])
    if good(history):
        for line in history['stdout'].splitlines():
            row = [part.strip() for part in line.split('|')]
            if len(row) >= 10 and row[0] == '244015' and row[1] == USER:
                qos |= names(row[3])
    selected_qos = sorted(qos)[:4]
    selected_reservations = sorted(reservations)[:2]
    for number, name in enumerate(selected_qos):
        query('own_associated_qos_' + str(number), ['sacctmgr', '-P', 'show', 'qos', 'where', 'name=' + name,
            'format=Name,Priority,MaxJobsPU,MaxSubmitJobsPU,MaxTRESPU,GrpTRES,MaxWall'])
    for number, name in enumerate(selected_reservations):
        query('own_job_linked_reservation_' + str(number), ['scontrol', 'show', 'reservation', name, '-o'])
    result = dict(scope='OWN_USER_HGPU2P_RESOURCES_AND_BILLING_METADATA', user=USER, uid=os.getuid(),
        hostname=os.uname().nodename, server_started_utc=began_utc, server_finished_utc=utc(),
        queries=RESULTS, association_accounts=sorted(own_accounts), selected_qos=selected_qos,
        qos_not_queried_due_to_bound=sorted(qos - set(selected_qos)),
        own_job_linked_reservations=selected_reservations,
        reservations_not_queried_due_to_bound=sorted(reservations - set(selected_reservations)),
        reservation_discovery_limit='Only reservations named by current own jobs; no global reservation listing.',
        monetary_unit_price='UNKNOWN_NOT_EXPOSED_BY_THIS_QUERY', balance='UNKNOWN_NOT_EXPOSED_BY_THIS_QUERY',
        allocation_is_not_permission_to_borrow_other_experiments=True, historical_job_is_not_remaining_allocation=True,
        billing_tres_is_not_currency=True, new_submissions=0, new_paid_jobs=0, requeue=0, cancellations=0,
        scientific_values_read=0, scientific_spatial_processing=0, model_calls=0,
        credential_or_home_scan=0, new_services_accessed=0, automatic_checks_enabled=False,
        elapsed_seconds=time.monotonic() - START)
    raw = json.dumps(result, ensure_ascii=False, separators=(',', ':'), allow_nan=False).encode()
    assert len(raw) <= 1048576 and len(RESULTS) <= 12 and time.monotonic() - START < 85
    print('OWN_RESOURCES_STATUS_BYTES=' + str(len(raw)))
    print('OWN_RESOURCES_STATUS_SHA256=' + hashlib.sha256(raw).hexdigest())
    print('OWN_RESOURCES_STATUS_ZLIB_BASE64=' + base64.b64encode(zlib.compress(raw)).decode())
    print('OWN_RESOURCES_STATUS_DONE', flush=True)


if __name__ == '__main__':
    main()

PY_OWN_RESOURCES
