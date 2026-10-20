#!/usr/bin/env bash
set -eo pipefail
python3 - <<'FIX_GRU_CONTEXT_AND_READ_003'
"""Resume the unchanged GRU candidate after its pre-training WorkDir rejection."""
import datetime
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path('/data1/home/sunyiq/zhenjiang_complete_comparison_fixed200_20261019_003')
RUNTIME = ROOT / 'sqrt_gru_recovery'
CASE = 'explicit_gru__historical_capacity'
RECORD = RUNTIME / 'records' / CASE
SLURM = Path('/usr/local/globle/softs/slurm/19.05.4.1/bin')
PREVIOUS = '245557'


def read(path):
    return json.loads(path.read_bytes())


def write(path, value):
    with path.open('x') as handle:
        json.dump(value, handle, sort_keys=True, indent=2)
        handle.write('\n')


def query(command):
    result = subprocess.run(list(map(str, command)), cwd=str(RUNTIME), capture_output=True, text=True, timeout=60)
    value = {'command': list(map(str, command)), 'returncode': result.returncode,
             'stdout': result.stdout, 'stderr': result.stderr}
    assert result.returncode == 0, json.dumps(value)
    return value


jobs_path = RUNTIME / 'records/scheduler_jobs.json'
jobs = read(jobs_path)
assert str(jobs[CASE]) == PREVIOUS
activation = read(ROOT / 'records/activation_report.json')
old_queue = [line.split('|') for line in activation['queue_after']['stdout'].splitlines() if line.startswith(PREVIOUS + '|')]
assert len(old_queue) == 1 and old_queue[0][3] == '/data1/home/sunyiq/hpc_mailbox'
assert old_queue[0][4] == str(RUNTIME / 'hpc/fixed200_case.slurm')
queue = query([SLURM / 'squeue', '-h', '-u', 'sunyiq', '-o', '%i|%j|%T|%Z|%o'])
assert not any(CASE in line or str(RUNTIME) in line for line in queue['stdout'].splitlines())
accounting = query([SLURM / 'sacct', '-n', '-X', '-j', PREVIOUS,
                    '--format=JobID,State,ExitCode,Start,End,NodeList', '-P'])
rows = [line.split('|') for line in accounting['stdout'].splitlines() if line.startswith(PREVIOUS + '|')]
assert len(rows) == 1 and rows[0][1:3] == ['FAILED', '1:0']
logs = [p.read_text(errors='replace') for p in (RUNTIME / 'logs').glob('*_' + PREVIOUS + '.out')]
assert len(logs) == 1 and "raise ValueError('allocation identity differs')" in logs[0]
assert not (RECORD / ('runtime_binding_' + PREVIOUS + '.json')).exists()
assert not list((RUNTIME / 'runs').glob('*/failure.json'))
for member, initial in read(RECORD / 'activation_starting_members.json').items():
    head = read(RUNTIME / 'runs' / member / 'checkpoint_head.json')
    assert head['completed_epochs'] == initial['completed_epochs']
    assert head['checkpoint_sha256'] == initial['checkpoint_sha256']
authority_path = RUNTIME / 'records/authorization.json'
authority = read(authority_path)
assert hashlib.sha256(authority_path.read_bytes()).hexdigest() == activation['cases'][CASE]['authorization_sha256']
script = RUNTIME / 'hpc/fixed200_case.slurm'
assert hashlib.sha256(script.read_bytes()).hexdigest() == authority['scheduler']['script_sha256']
record = {'schema': 'fixed200-submission-context-repair-v1', 'case': CASE, 'previous_job': PREVIOUS,
          'at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'queue': queue,
          'accounting': accounting, 'previous_log': logs[0],
          'previous_workdir': old_queue[0][3], 'corrected_workdir': str(RUNTIME),
          'authorization_and_script_unchanged': True, 'checkpoint_epochs_unchanged': True,
          'new_optimizer_steps_before_repair': 0}
write(RECORD / 'submission_context_repair.attempt.json', record)
try:
    submitted = query([SLURM / 'xbatch', script])
except Exception as error:
    write(RECORD / 'submission_context_repair.response.json', {'status': 'uncertain_reconcile_readonly', 'error': str(error)})
    raise
write(RECORD / 'submission_context_repair.response.json', submitted)
match = re.fullmatch(r'Submitted batch job ([0-9]+)\s*', submitted['stdout'])
assert match, 'uncertain submission: reconcile without replay'
write(RUNTIME / 'records/scheduler_jobs_before_context_repair.json', jobs)
jobs[CASE] = match.group(1)
temporary = jobs_path.with_suffix('.json.tmp')
write(temporary, jobs)
temporary.replace(jobs_path)
record.update(status='submission_workdir_repaired_same_frozen_script', job_id=match.group(1))
write(RECORD / 'submission_context_repair.confirmed.json', record)
print(json.dumps(record, sort_keys=True), flush=True)

"""Read fixed-200 allocation and committed-epoch evidence without loading tensors.

Example on HPC: python -B read_status.py
Reads the two activated cases, checkpoint heads/events and small record files.
Prints a status snapshot only; no scheduler submission or source writes.
"""
import datetime
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path('/data1/home/sunyiq/zhenjiang_complete_comparison_fixed200_20261019_003')
SLURM = Path('/usr/local/globle/softs/slurm/19.05.4.1/bin')
CASES = {'legacy_lstm__historical_capacity': 'base',
         'explicit_gru__historical_capacity': 'sqrt_gru_recovery'}


def read(path):
    return json.loads(path.read_bytes())


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def query(command):
    result = subprocess.run(list(map(str, command)), capture_output=True, text=True, timeout=45)
    return {'command': list(map(str, command)), 'returncode': result.returncode,
            'stdout': result.stdout, 'stderr': result.stderr}


report = {'schema': 'fixed200-activation-status-v1', 'root': str(ROOT),
          'checked_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'checkpoints_loaded': False, 'evaluation_values_read': False, 'cases': {}, 'errors': []}
report['queue'] = query([SLURM / 'squeue', '-h', '-u', 'sunyiq', '-o', '%i|%j|%T|%Z|%e|%l|%N|%R'])
for case, variant in CASES.items():
    runtime = ROOT / variant
    record = runtime / 'records' / case
    try:
        initial = read(record / 'activation_starting_members.json')
        job = str(read(runtime / 'records/scheduler_jobs.json')[case])
        auth = read(runtime / 'records/authorization.json')
        row = {'case': case, 'root': str(runtime), 'job_id': job,
               'authorization_sha256': sha(runtime / 'records/authorization.json'),
               'authorization': auth, 'migration_manifest': read(record / 'migration_manifest.json'),
               'data_preparation_complete': read(runtime / 'records/data_preparation_complete.json'),
               'scheduler_script': (runtime / 'hpc/fixed200_case.slurm').read_text(),
               'device_identity': auth['device_identity'], 'members': {},
               'queue_rows': [line for line in report['queue']['stdout'].splitlines() if line.startswith(job + '|')],
               'failure_records': {}}
        allocation = record / ('runtime_binding_' + job + '.json')
        if allocation.exists():
            row['runtime_binding'] = read(allocation)
            assert row['runtime_binding']['device_identity'] == auth['device_identity']
        for name in ('progress.json', 'training_complete.json', 'selected_rates_2021.json',
                     'scheduler_slice_end_' + job + '.json', 'submission_context_repair.confirmed.json'):
            if (record / name).exists():
                row[name] = read(record / name)
        source_outcome = record / 'tune_foundation_group_outcome.json'
        if source_outcome.exists():
            source = read(source_outcome)
            row['tuning_foundation_source'] = {'seal_epochs': source['seal']['epochs'],
                'members': {name: {'epochs': value['epochs'], 'best_epoch': value['best_epoch'],
                           'checkpoint_sha256': value['checkpoint_sha256']}
                            for name, value in source['members'].items()}}
            assert row['tuning_foundation_source']['seal_epochs'] == 400
        for member, start in initial.items():
            folder = runtime / 'runs' / member
            head = read(folder / 'checkpoint_head.json')
            anchor = read(folder / 'continuation_anchor.json')
            assert anchor['initial_checkpoint_sha256'] == start['checkpoint_sha256']
            assert anchor['initial_epochs'] == start['completed_epochs']
            assert sha(folder / 'config.json') == start['config_sha256']
            assert sha(folder / 'migration_source.json') == start['receipt_sha256']
            n = head['completed_epochs']
            assert start['completed_epochs'] <= n <= 200
            item = {'initial_epochs': start['completed_epochs'], 'completed_epochs': n,
                    'new_complete_epochs': n - start['completed_epochs'],
                    'checkpoint_sha256_from_committed_head': head['checkpoint_sha256'],
                    'initial_identity_and_config_preserved': True}
            if n > start['completed_epochs']:
                event = read(folder / 'checkpoint_events' / (head['checkpoint_sha256'][:16] + '.json'))
                assert event['checkpoint_sha256'] == head['checkpoint_sha256']
                assert event['completed_epochs'] == n and event['previous_epochs'] == n - 1
                assert event['anchor_sha256'] == head['anchor_sha256'] == sha(folder / 'continuation_anchor.json')
                item['new_epoch_event'] = event
            if (folder / 'failure.json').exists():
                row['failure_records'][member] = read(folder / 'failure.json')
            row['members'][member] = item
        row['new_complete_member_epochs'] = sum(v['new_complete_epochs'] for v in row['members'].values())
        row['members_with_new_complete_epoch'] = sum(v['new_complete_epochs'] > 0 for v in row['members'].values())
        row['tune_branch_200_complete_members'] = sum(v['completed_epochs'] == 200 for v in row['members'].values())
        row['actual_training_progress_confirmed'] = bool(row.get('runtime_binding') and row['new_complete_member_epochs'] > 0)
        row['logs'] = []
        for path in (runtime / 'logs').glob('*_' + job + '.out'):
            with path.open('rb') as handle:
                handle.seek(max(0, path.stat().st_size - 7000))
                row['logs'].append({'path': str(path), 'tail': handle.read().decode('utf-8', errors='replace')})
        report['cases'][case] = row
    except Exception as error:
        report['errors'].append({'case': case, 'type': type(error).__name__, 'message': str(error)})
jobs = [v['job_id'] for v in report['cases'].values()]
if jobs:
    report['accounting'] = query([SLURM / 'sacct', '-n', '-X', '-j', ','.join(jobs),
                                  '--format=JobID,State,ExitCode,Start,End,NodeList', '-P'])
report['summary'] = {'cases': len(report['cases']),
    'cases_with_new_complete_epoch': sum(v['actual_training_progress_confirmed'] for v in report['cases'].values()),
    'new_complete_member_epochs': sum(v['new_complete_member_epochs'] for v in report['cases'].values()),
    'members_with_new_complete_epoch': sum(v['members_with_new_complete_epoch'] for v in report['cases'].values()),
    'tune_branch_200_complete_members': sum(v['tune_branch_200_complete_members'] for v in report['cases'].values()),
    'failure_files': sum(len(v['failure_records']) for v in report['cases'].values())}
print(json.dumps(report, sort_keys=True), flush=True)

FIX_GRU_CONTEXT_AND_READ_003
