#!/usr/bin/env bash
# One bounded metadata-only observation of the sole newly authorized experiment.
set -e -o pipefail
export PYTHONDONTWRITEBYTECODE=1
export PYTHONNOUSERSITE=1
python3 -B - <<'PY'
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import sqlite3
import stat
import subprocess

ROOT = Path('/data1/home/sunyiq/zhenjiang_matched_legacy_process_20260908_001')
CONTRACT_SHA = '8c3ef366a8dbbf8b9e18704d1dca8a7bd887ca3afd745a0a9c495ed1a1d709cb'
FAMILY = 'ZHENJIANG_MATCHED_LEGACY_PROCESS_MODEL_20260907'

def utc_now():
    return datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')

def ordinary(path):
    for component in reversed((path,) + tuple(path.parents)):
        if stat.S_ISLNK(component.lstat().st_mode):
            raise ValueError('redirected metadata path')
    return path

def metadata(relative):
    path = ROOT / relative
    try:
        ordinary(path)
        info = path.stat()
        if not stat.S_ISREG(info.st_mode) or info.st_size > 2_000_000:
            raise ValueError('metadata is not a bounded regular file')
        with path.open('rb') as handle:
            raw = handle.read(2_000_001)
        if len(raw) > 2_000_000:
            raise ValueError('metadata read exceeds bound')
        return {'status': 'read', 'byte_count': len(raw),
                'sha256': hashlib.sha256(raw).hexdigest(), 'value': json.loads(raw)}
    except FileNotFoundError:
        return {'status': 'absent'}
    except Exception as error:
        return {'status': 'unavailable', 'error_type': type(error).__name__}

report = {'schema_version': 1, 'kind': 'read_only_matched_legacy_evidence',
          'root': str(ROOT), 'execution_contract_sha256': CONTRACT_SHA,
          'observed_at_utc': utc_now(), 'new_formal_data_reads_by_query': 0,
          'checkpoint_reads_by_query': 0, 'filesystem_writes_by_query': 0}
ordinary(ROOT)
paths = ['evidence/deployment_verified.json', 'evidence/submission_attempt_001.json',
         'evidence/submission_outcome.json', 'evidence/submission_receipt.json',
         'evidence/job_attempt_001/started.json',
         'evidence/job_attempt_001/completion_receipt.json']
for seed in (17, 29, 43):
    paths += [f'evidence/seed_attempts/seed_{seed}/{name}' for name in
              ('attempt_started.json', 'failure.json', 'completion_receipt.json')]
    paths += [f'app/artifacts/seed_{seed}/{name}' for name in
              ('completion_manifest.json', 'environment_manifest.json')]
report['metadata'] = {name: metadata(name) for name in paths}
submission = report['metadata']['evidence/submission_receipt.json']
value = submission.get('value', {})
job_id = value.get('job_id', '')
if (submission['status'] != 'read' or not isinstance(job_id, str)
        or not re.fullmatch(r'[0-9]+', job_id)
        or value.get('execution_contract_sha256') != CONTRACT_SHA
        or value.get('experiment_family') != FAMILY or value.get('status') != 'submitted'):
    report['job_identity_status'] = 'unverified_no_scheduler_or_log_query'
else:
    report['job_id'] = job_id
    report['scheduler'] = {}
    commands = {
        'squeue': ['squeue', '-j', job_id, '-h', '-o', '%i|%T|%M|%l|%R'],
        'sacct': ['sacct', '-n', '-P', '-j', job_id,
                  '--format=JobIDRaw,State,ExitCode,Elapsed,Start,End,AllocTRES'],
    }
    for name, command in commands.items():
        try:
            result = subprocess.run(command, capture_output=True, timeout=10, check=False,
                                    env=dict(os.environ, LC_ALL='C'))
            report['scheduler'][name] = {'returncode': result.returncode,
                'stdout': result.stdout[:64000].decode('utf-8', errors='replace'),
                'stderr': result.stderr[:16000].decode('utf-8', errors='replace')}
        except Exception as error:
            report['scheduler'][name] = {'error_type': type(error).__name__}
    report['logs'] = {}
    for suffix in ('out', 'err'):
        name = f'logs/slurm-{job_id}.{suffix}'
        path = ROOT / name
        try:
            ordinary(path)
            info = path.stat()
            if not stat.S_ISREG(info.st_mode):
                raise ValueError('log is not a regular file')
            with path.open('rb') as handle:
                raw = handle.read(2_000_000)
            lines = raw.decode('utf-8', errors='replace').splitlines()
            report['logs'][name] = {'status': 'read', 'bytes_read': len(raw),
                'file_size_at_open': info.st_size, 'prefix_truncated': info.st_size > len(raw),
                'optimizer_update_lines': [line for line in lines if
                    '[TRAINING_PROGRESS] first_batch_optimizer_step_completed' in line][:108],
                'last_30_lines_of_read_prefix': lines[-30:]}
        except FileNotFoundError:
            report['logs'][name] = {'status': 'absent'}
        except Exception as error:
            report['logs'][name] = {'status': 'unavailable', 'error_type': type(error).__name__}

# Do not import the ledger class: its constructor creates/updates schema.
# The frozen new ledger uses rollback journals, not WAL. Refuse WAL before
# connecting so a read cannot create shared-memory sidecars. mode=ro also
# refuses journal recovery requiring writes. The two SELECTs share one snapshot.
ledger = ROOT / 'evidence/formal_data_usage.sqlite3'
try:
    ordinary(ledger)
    if not ledger.is_file():
        raise ValueError('ledger is not a regular file')
    with ledger.open('rb') as handle:
        header = handle.read(20)
    if header[:16] != b'SQLite format 3\x00' or header[18:20] != b'\x01\x01':
        raise ValueError('ledger is not a rollback-journal SQLite database')
    connection = sqlite3.connect(ledger.as_uri() + '?mode=ro', uri=True,
                                 timeout=2, isolation_level=None)
    try:
        connection.execute('PRAGMA query_only=ON')
        connection.execute('BEGIN')
        groups = connection.execute('SELECT event_type, COUNT(*), '
            'COALESCE(SUM(byte_count),0), COALESCE(SUM(bytes_read),0) '
            'FROM usage_events GROUP BY event_type ORDER BY event_type').fetchall()
        scopes = connection.execute('SELECT DISTINCT authorization_id, purpose, time_partition '
                                    'FROM usage_events').fetchall()
        report['usage_ledger'] = {'status': 'read_only_transaction',
            'observed_at_utc': utc_now(), 'event_groups': [dict(zip(
                ('event_type', 'count', 'authorized_byte_count', 'bytes_read'), row)) for row in groups],
            'scopes': [dict(zip(('authorization_id', 'purpose', 'time_partition'), row)) for row in scopes]}
    finally:
        connection.close()
except FileNotFoundError:
    report['usage_ledger'] = {'status': 'absent'}
except Exception as error:
    report['usage_ledger'] = {'status': 'unavailable', 'error_type': type(error).__name__}
report['finished_at_utc'] = utc_now()
print('READ_ONLY_MATCHED_EVIDENCE')
print(json.dumps(report, indent=2, ensure_ascii=False, sort_keys=True))
PY
