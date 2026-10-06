#!/usr/bin/env bash
# Read-only monitoring: no data inputs or checkpoint deserialization.
set -euo pipefail
cd /data1/home/sunyiq/zhenjiang_complete_comparison_20261006_002
python3 - <<'PY'
import datetime
import hashlib
import json
import pathlib
import re
import subprocess

ROOT = pathlib.Path.cwd()
UTC = datetime.timezone.utc
BEIJING = datetime.timezone(datetime.timedelta(hours=8))
ERRORS = []


def relative(path):
    return path.relative_to(ROOT).as_posix()


def error(path, exc):
    record = {'path': relative(path), 'error_type': type(exc).__name__, 'error': str(exc)[:1200]}
    ERRORS.append(record)
    return record


def metadata(path):
    try:
        stat = path.stat()
        moment = datetime.datetime.fromtimestamp(stat.st_mtime, UTC)
        return {'exists': True, 'bytes': stat.st_size, 'mtime_ns': stat.st_mtime_ns,
                'mtime_utc': moment.isoformat(), 'mtime_beijing': moment.astimezone(BEIJING).isoformat()}
    except FileNotFoundError:
        return {'exists': False}
    except Exception as exc:
        return {'exists': None, 'error': error(path, exc)}


def read_json(path):
    info = metadata(path)
    record = {'path': relative(path), 'stat': info}
    if not info.get('exists'):
        return record, None
    try:
        raw = path.read_bytes()
        record['sha256'] = hashlib.sha256(raw).hexdigest()
        value = json.loads(raw)
        record['json_valid'] = True
        return record, value
    except Exception as exc:
        record['json_valid'] = False
        record['error'] = error(path, exc)
        return record, None


def json_record(path):
    record, value = read_json(path)
    if value is not None:
        record['value'] = value
    return record


def run_command(command):
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=30)
        return {'command': command, 'returncode': result.returncode,
                'stdout': result.stdout[:60000], 'stderr': result.stderr[:10000],
                'stdout_truncated': len(result.stdout) > 60000}
    except Exception as exc:
        return {'command': command, 'error_type': type(exc).__name__, 'error': str(exc)[:1200]}


now = datetime.datetime.now(UTC)
report = {'status': 'read_only_training_snapshot', 'root': str(ROOT),
          'checked_at_utc': now.isoformat(), 'checked_at_beijing': now.astimezone(BEIJING).isoformat(),
          'evaluation_values_read': False, 'data_inputs_read': False,
          'checkpoints_loaded': False, 'checkpoint_stat_only': True}

job_record, job_mapping = read_json(ROOT / 'records/scheduler_jobs.json')
report['scheduler_jobs_file'] = job_record
report['scheduler_jobs'] = job_mapping
job_ids = []
if isinstance(job_mapping, dict):
    for key, value in job_mapping.items():
        if re.fullmatch(r'[0-9]+', str(value)):
            job_ids.append(str(value))
        else:
            ERRORS.append({'path': 'records/scheduler_jobs.json', 'error': 'invalid job id', 'key': str(key)})
job_ids = sorted(set(job_ids), key=int)
report['own_job_ids'] = job_ids
report['scheduler_queries'] = []
if job_ids:
    own_ids = ','.join(job_ids)
    report['scheduler_queries'] = [
        run_command(['squeue', '-h', '-j', own_ids, '-o', '%i|%j|%T|%R|%M|%N|%b']),
        run_command(['sacct', '-n', '-X', '-j', own_ids,
                     '--format=JobID,JobName,State,ExitCode,Elapsed,NodeList,Reason', '-P'])]

report['identities'] = {}
for name in ['records/authorization.json', 'records/data_preparation_complete.json',
             'configs/protocol-v3.json', 'configs/registry-v3.json']:
    record, value = read_json(ROOT / name)
    if isinstance(value, dict):
        record['binding_fields'] = {key: value[key] for key in
            ('status', 'protocol_sha256', 'code_hash', 'scientific_factors_sha256',
             'execution_policy', 'evaluation_values_read', 'evaluation_year_reads',
             'source_files', 'training_authority', 'version') if key in value}
        if name.endswith('registry-v3.json'):
            record['logical_runs'] = len(value.get('runs', []))
            record['gates'] = len(value.get('gates', []))
    report['identities'][name] = record
try:
    source_files = sorted([*ROOT.joinpath('src').glob('*.py'),
                           *ROOT.joinpath('scripts').glob('*.py'),
                           *ROOT.joinpath('vendor/pytides').glob('*.py')])
    hashes = {relative(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in source_files}
    canonical = json.dumps(hashes, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()
    report['actual_code_identity'] = {'code_hash': hashlib.sha256(canonical).hexdigest(),
                                      'source_file_count': len(hashes)}
    authorization_record, authorization = read_json(ROOT / 'records/authorization.json')
    authorized_hash = authorization.get('code_hash') if isinstance(authorization, dict) else None
    report['actual_code_identity']['authorized_code_hash'] = authorized_hash
    report['actual_code_identity']['matches_authorized_code'] = (
        report['actual_code_identity']['code_hash'] == authorized_hash) if authorized_hash else None
except Exception as exc:
    report['actual_code_identity'] = {'error_type': type(exc).__name__, 'error': str(exc)[:1200]}

report['cases'] = {}
case_names = [key for key in (job_mapping or {}) if key != 'preparation'] if isinstance(job_mapping, dict) else []
case_names = sorted(set(case_names) | {path.parent.name for path in ROOT.joinpath('records').glob('*/progress.json')})
for case in case_names:
    if not re.fullmatch(r'[A-Za-z0-9_]+', case):
        ERRORS.append({'case': case, 'error': 'unsafe case name ignored'})
        continue
    folder = ROOT / 'records' / case
    detail = {'progress': json_record(folder / 'progress.json'),
              'training_complete': json_record(folder / 'training_complete.json'),
              'selected_rates': json_record(folder / 'selected_rates_2021.json'),
              'allocations': [json_record(path) for path in sorted(folder.glob('allocation_*.json'))],
              'outcomes': []}
    for path in sorted(folder.glob('*_outcome.json')):
        record, value = read_json(path)
        if isinstance(value, dict):
            members = value.get('members', {})
            seal = value.get('seal', {})
            if not isinstance(members, dict):
                record['error'] = error(path, ValueError('outcome members are not an object'))
                detail['outcomes'].append(record)
                continue
            record.update(status=value.get('status'), member_count=len(members), seal=seal)
            record['members'] = {}
            for member, result in members.items():
                if not isinstance(result, dict):
                    record['members'][member] = {'error': 'member result is not an object'}
                    continue
                values = result.get('validation_mae', [])
                record['members'][member] = {key: result.get(key) for key in
                    ('status', 'epochs', 'budget_final', 'best_epoch', 'method',
                     'learning_rate', 'checkpoint_sha256', 'checkpoint_path')}
                record['members'][member]['validation_history_length'] = len(values) if isinstance(values, list) else None
        detail['outcomes'].append(record)
    report['cases'][case] = detail

report['runs'] = {}
for folder in sorted(ROOT.joinpath('runs').glob('*')):
    if not folder.is_dir():
        continue
    detail = {'continuation_checkpoint_stat': metadata(folder / 'continuation.pt'),
              'temporary_continuation_stat': metadata(folder / 'continuation.pt.tmp'),
              'best_checkpoint_stat': metadata(folder / 'best.pt'),
              'epoch_checkpoint_stats': {path.name: metadata(path) for path in sorted(folder.glob('epoch_*.pt'))},
              'first_optimizer_step': json_record(folder / 'first_optimizer_step.json'),
              'failure': json_record(folder / 'failure.json')}
    config_record, config = read_json(folder / 'config.json')
    if isinstance(config, dict):
        effective = config.get('effective_config', {})
        config_record['binding_fields'] = {key: effective.get(key) for key in
            ('code_hash', 'training_data_hash', 'normalization_hash', 'parent_hash',
             'parent_run_id', 'device_identity', 'scheduler_continuation', 'learning_rate')}
        config_record['registration'] = config.get('registration')
        config_record['protocol_sha256'] = config.get('protocol_sha256')
    detail['config'] = config_record
    path = folder / 'metrics.json'
    metrics = {'path': relative(path), 'stat': metadata(path)}
    if metrics['stat'].get('exists'):
        try:
            # Histories precede bulky per-batch training metrics. Read just this prefix.
            with path.open('rb') as stream:
                prefix = stream.read(131072).decode('utf-8')
            match = re.search(r'"validation_mae_cm"\s*:\s*', prefix)
            if match is None:
                raise ValueError('validation history missing from metrics prefix')
            values, end = json.JSONDecoder().raw_decode(prefix[match.end():])
            if not isinstance(values, list):
                raise ValueError('validation history is not a list')
            metrics.update(completed_epochs=len(values), validation_history_length=len(values),
                           recent_validation_mae_cm=values[-5:],
                           validation_history_sha256=hashlib.sha256(json.dumps(values, separators=(',', ':')).encode()).hexdigest(),
                           validation_prefix_parsed=True, full_json_validity_checked=False)
        except Exception as exc:
            metrics['error'] = error(path, exc)
    detail['metrics'] = metrics
    report['runs'][folder.name] = detail

report['logs'] = []
for path in sorted(ROOT.joinpath('logs').glob('*.out')):
    item = {'path': relative(path), 'stat': metadata(path)}
    try:
        with path.open('rb') as stream:
            stream.seek(max(0, path.stat().st_size - 20000))
            tail = stream.read().decode('utf-8', errors='replace')
        item['tail'] = tail
        item['error_lines_in_tail'] = [line[:1800] for line in tail.splitlines() if
            re.search(r'Traceback|Error|Exception|CUDA|out of memory|training_stopped|slurmstepd|Killed', line, re.I)][-15:]
    except Exception as exc:
        item['error'] = error(path, exc)
    report['logs'].append(item)

report['summary'] = {'case_count': len(report['cases']), 'run_directories': len(report['runs']),
    'runs_with_completed_epoch_history': sum(bool(v['metrics'].get('completed_epochs')) for v in report['runs'].values()),
    'completed_member_epochs': sum(v['metrics'].get('completed_epochs', 0) for v in report['runs'].values()),
    'runs_with_failure_file': sum(v['failure']['stat'].get('exists') is True for v in report['runs'].values()),
    'complete_case_records': sum(v['training_complete']['stat'].get('exists') is True for v in report['cases'].values())}
report['read_errors'] = ERRORS
report['finished_at_utc'] = datetime.datetime.now(UTC).isoformat()
print(json.dumps(report, ensure_ascii=True, sort_keys=True))
PY
