#!/usr/bin/env bash
set -eo pipefail
python3 - <<'READ_FIXED200_003'
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

READ_FIXED200_003

python3 - <<'EXPORT_003_PRIORITY_COMPLETE'
"""Read-only, stable complete-state export for the four existing tuning runs."""
import base64
import datetime
import hashlib
import io
import json
from pathlib import Path
import tarfile
import time

ROOT = Path('/data1/home/sunyiq/zhenjiang_complete_comparison_fixed200_20261019_003/base')
CASE = 'legacy_lstm__historical_capacity'
METHODS = ('encoder_fixed', 'encoder_joint', 'filter_fixed', 'filter_joint')
files = {}
sources = []
members = []
sha = lambda b: hashlib.sha256(b).hexdigest()

def add_raw(raw, name, source):
    if name in files:
        assert files[name] == raw
        return
    files[name] = raw
    sources.append({'path': name, 'source_path': str(source), 'bytes': len(raw), 'sha256': sha(raw)})

def add(path, name, expected=None):
    raw = path.read_bytes()
    if expected is not None:
        assert sha(raw) == expected, str(path)
    add_raw(raw, name, path)

for folder in ('src', 'scripts', 'vendor/pytides'):
    for path in sorted((ROOT / folder).glob('*.py')):
        add(path, 'runtime/' + path.relative_to(ROOT).as_posix())
for name in ('configs/protocol-v3.json', 'configs/registry-v3.json',
             'configs/stage_source_admission.json', 'records/authorization.json',
             'records/data_preparation_complete.json'):
    add(ROOT / name, 'runtime/' + name)
prep = json.loads((ROOT / 'records/data_preparation_complete.json').read_bytes())
manifest_path = ROOT / 'prepared/tuning/manifest.json'
manifest = json.loads(manifest_path.read_bytes())
add(manifest_path, 'source_tuning_manifest.json', prep['reports']['tuning']['manifest_file_sha256'])
for item in manifest['files']:
    assert set(item['years']).issubset({2017, 2018, 2019, 2020, 2021})
    add(Path(item['path']), 'inputs/tuning/' + Path(item['path']).name, item['sha256'])

for method in METHODS:
    run = CASE + '__tune_branch__' + method + '__s101__lr0p001'
    folder = ROOT / 'runs' / run
    assert not (folder / 'failure.json').exists(), 'failed source retained; no automatic export admission'
    stable = None
    for attempt in range(5):
        head_raw = (folder / 'checkpoint_head.json').read_bytes()
        head = json.loads(head_raw)
        names = ['config.json', 'continuation.pt', 'initial_continuation.pt',
                 'continuation_anchor.json', 'migration_source.json']
        # Export all immutable lineage support files, excluding superseded snapshots,
        # derived metrics and in-progress temporary files.
        names += [p.relative_to(folder).as_posix() for p in folder.rglob('*')
                  if p.is_file() and (p.parent.name == 'checkpoint_events'
                    or p.name.startswith('source_') or p.name == 'whitening.json')]
        raw_files = {name: (folder / name).read_bytes() for name in sorted(set(names))}
        if (head_raw == (folder / 'checkpoint_head.json').read_bytes()
                and sha(raw_files['continuation.pt']) == head['checkpoint_sha256']):
            stable = raw_files
            break
        time.sleep(1)
    assert stable is not None, 'source boundary busy; no source changes made'
    assert 0 < head['completed_epochs'] <= 200
    stable['checkpoint_head.json'] = head_raw
    if head['completed_epochs'] == 200:
        stable['epoch_200.pt'] = (folder / 'epoch_200.pt').read_bytes()
    for name, raw in stable.items():
        add_raw(raw, 'sources/' + run + '/' + name, folder / name)
    config = json.loads(stable['config.json'])
    effective = config['effective_config']
    assert config['registration']['method'] == method and effective['learning_rate'] == .001
    parent = Path(effective['parent_checkpoint'])
    add(parent, 'parents/' + effective['parent_hash'] + '.pt', effective['parent_hash'])
    members.append({'run_id': run, 'method': method, 'source_epochs': head['completed_epochs'],
                    'head': head, 'config_sha256': sha(stable['config.json']),
                    'parent_hash': effective['parent_hash'], 'source_path': str(folder)})

buffer = io.BytesIO()
with tarfile.open(fileobj=buffer, mode='w:gz') as archive:
    for name, raw in files.items():
        info = tarfile.TarInfo(name); info.size = len(raw); info.mode = 0o644
        archive.addfile(info, io.BytesIO(raw))
binary = buffer.getvalue()
report = {'schema': '003-priority-complete-source-export-v1',
          'at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'files': sources, 'members': members, 'archive_bytes': len(binary),
          'archive_sha256': sha(binary), 'source_writes': 0, 'training_submissions': 0,
          'checkpoint_tensors_loaded': False, 'years_2022_2023_2024_read': False}
print(json.dumps(report), flush=True)
assert len(binary) < 8_000_000, 'bounded transfer limit; no source writes or training'
print('BEGIN_003_PRIORITY_ARCHIVE_BASE64', flush=True)
encoded = base64.b64encode(binary).decode()
for pos in range(0, len(encoded), 65536):
    print(encoded[pos:pos+65536], flush=True)
print('END_003_PRIORITY_ARCHIVE_BASE64', flush=True)

EXPORT_003_PRIORITY_COMPLETE
