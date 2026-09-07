#!/usr/bin/env bash
# One bounded metadata-only reconciliation of the sole uncertain submission.
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

ROOT = Path('/data1/home/sunyiq/zhenjiang_matched_legacy_process_20260907_001')
CONTRACT_SHA = 'd52fea4d1400fa00a78d9842cc1cf38e292bd31dfc98e19ab8529d1c62234de1'
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

report = {'schema_version': 1, 'kind': 'read_only_matched_submission_uncertainty',
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

# Submission uncertainty: inspect only this attempt's raw wrapper return and new
# root log names. Never manufacture a valid submission receipt or resubmit.
report['raw_submission_return'] = {}
raw_stdout = ''
for name in ('submission_stdout.bin', 'submission_stderr.bin'):
    path = ROOT / 'evidence' / name
    try:
        ordinary(path)
        info = path.stat()
        if not stat.S_ISREG(info.st_mode) or info.st_size > 64000:
            raise ValueError('raw submission return is not a bounded regular file')
        with path.open('rb') as handle:
            raw = handle.read(64001)
        if len(raw) > 64000:
            raise ValueError('raw submission return exceeds bound')
        decoded = raw.decode('utf-8', errors='replace')
        report['raw_submission_return'][name] = {'status': 'read',
            'byte_count': len(raw), 'sha256': hashlib.sha256(raw).hexdigest(), 'text': decoded}
        if name == 'submission_stdout.bin':
            raw_stdout = decoded
    except FileNotFoundError:
        report['raw_submission_return'][name] = {'status': 'absent'}
    except Exception as error:
        report['raw_submission_return'][name] = {'status': 'unavailable',
                                                'error_type': type(error).__name__}
candidate_ids = set(re.findall(r'^Submitted batch job ([0-9]+)\r?$', raw_stdout, re.MULTILINE))
log_names = []
try:
    log_directory = ordinary(ROOT / 'logs')
    for index, path in enumerate(log_directory.iterdir()):
        if index >= 8:
            raise ValueError('unexpected number of new-root log entries')
        log_names.append(path.name)
        matched = re.fullmatch(r'slurm-([0-9]+)\.(out|err)', path.name)
        if matched:
            candidate_ids.add(matched.group(1))
    report['new_root_log_names'] = sorted(log_names)
except Exception as error:
    report['new_root_log_names_error_type'] = type(error).__name__
    candidate_ids.clear()
report['job_ids_from_raw_return_or_fixed_root_log_names'] = sorted(candidate_ids)
if 'job_id' not in report and len(candidate_ids) == 1:
    candidate = next(iter(candidate_ids))
    report['inferred_job_id_not_validated_submission'] = candidate
    report['uncertain_submission_scheduler'] = {}
    for name, command in {
        'squeue': ['squeue', '-j', candidate, '-h', '-o', '%i|%T|%M|%l|%R'],
        'sacct': ['sacct', '-n', '-P', '-j', candidate,
                  '--format=JobIDRaw,State,ExitCode,Elapsed,Start,End,AllocTRES'],
    }.items():
        try:
            result = subprocess.run(command, capture_output=True, timeout=10, check=False,
                                    env=dict(os.environ, LC_ALL='C'))
            report['uncertain_submission_scheduler'][name] = {'returncode': result.returncode,
                'stdout': result.stdout[:64000].decode('utf-8', errors='replace'),
                'stderr': result.stderr[:16000].decode('utf-8', errors='replace')}
        except Exception as error:
            report['uncertain_submission_scheduler'][name] = {'error_type': type(error).__name__}
    report['uncertain_submission_logs'] = {}
    for suffix in ('out', 'err'):
        name = f'logs/slurm-{candidate}.{suffix}'
        try:
            path = ordinary(ROOT / name)
            if not path.is_file():
                raise ValueError('candidate log is not a regular file')
            with path.open('rb') as handle:
                raw = handle.read(64000)
            report['uncertain_submission_logs'][name] = {
                'status': 'read', 'bytes_read': len(raw),
                'text_prefix': raw.decode('utf-8', errors='replace')}
        except FileNotFoundError:
            report['uncertain_submission_logs'][name] = {'status': 'absent'}
        except Exception as error:
            report['uncertain_submission_logs'][name] = {
                'status': 'unavailable', 'error_type': type(error).__name__}

report['finished_at_utc'] = utc_now()
print('READ_ONLY_MATCHED_EVIDENCE')
print(json.dumps(report, indent=2, ensure_ascii=False, sort_keys=True))
PY
