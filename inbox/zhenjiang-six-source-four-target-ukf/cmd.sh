#!/usr/bin/env bash
set -eo pipefail
python3 - <<'INDEPENDENT_REPAIR_MONITOR'
"""Read the independent repair's scheduler, provenance and checkpoint metadata."""
import datetime
import hashlib
import json
import subprocess
import traceback
from pathlib import Path


ROOT = Path('/data1/home/sunyiq/zhenjiang_complete_comparison_fixed200_20261019_003/sqrt_gru_recovery')
CASE = 'explicit_gru__historical_capacity'
REPAIR = ROOT / 'records' / CASE / 'repairs/projection_repair_20261105_001'
SLURM = Path('/usr/local/globle/softs/slurm/19.05.4.1/bin')


def read(path):
    return json.loads(path.read_bytes())


def sha(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def query(args):
    result = subprocess.run(list(map(str, args)), capture_output=True, text=True, timeout=60)
    return {'command': list(map(str, args)), 'returncode': result.returncode,
            'stdout': result.stdout, 'stderr': result.stderr}


def code_identity():
    paths = sorted([*ROOT.joinpath('src').glob('*.py'), *ROOT.joinpath('scripts').glob('*.py'),
                    *ROOT.joinpath('vendor/pytides').glob('*.py')])
    values = {path.relative_to(ROOT).as_posix(): sha(path) for path in paths}
    return hashlib.sha256(json.dumps(values, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()).hexdigest()


out = {'schema': '003-independent-projection-repair-monitor-v1',
       'at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'case': CASE,
       'errors': [], 'checkpoint_tensors_loaded': False, 'members': {}, 'new_failures': {}, 'usage': {},
       'job_bindings': {}}
try:
    admission_path = REPAIR / 'ADMISSION.json'
    admission, plan = read(admission_path), read(REPAIR / 'plan.json')
    out['admission_sha256'] = sha(admission_path)
    out['actual_code_hash'] = code_identity()
    out['expected_code_hash'] = admission['repair_code_hash']
    out['source_identity_matches'] = out['actual_code_hash'] == out['expected_code_hash']
    runner = ROOT / plan['runner_path']
    out['runner_sha256'] = sha(runner)
    out['runner_identity_matches'] = out['runner_sha256'] == plan['runner_sha256']
    out['validation_report_sha256'] = sha(Path(admission['validation']['report_path']))
    out['validation_report_matches'] = out['validation_report_sha256'] == admission['validation']['report_sha256']
    job = str(read(ROOT / 'records/scheduler_jobs.json')[CASE])
    out['job_id'] = job
    binding_path = REPAIR / 'job_bindings' / (job + '.json')
    out['job_binding'] = read(binding_path) if binding_path.is_file() else None
    runtime_path = ROOT / 'records' / CASE / ('runtime_binding_' + job + '.json')
    out['runtime_binding'] = read(runtime_path) if runtime_path.is_file() else None
    out['queue'] = query([SLURM / 'squeue', '-h', '-u', 'sunyiq', '-o', '%i|%j|%T|%Z|%e|%l|%N|%R'])
    out['accounting'] = query([SLURM / 'sacct', '-n', '-X', '-j', job,
                               '--format=JobID,State,ExitCode,Start,End,NodeList', '-P'])
    for path in sorted((REPAIR / 'job_bindings').glob('*.json')):
        out['job_bindings'][path.stem] = {'sha256': sha(path), 'record': read(path)}
    for path in sorted((REPAIR / 'new_failures').glob('*.json')):
        out['new_failures'][path.name] = {'sha256': sha(path), 'record': read(path)}
    for path in sorted((REPAIR / 'usage').glob('*.json')):
        out['usage'][path.name] = {'sha256': sha(path), 'record': read(path)}
    for exp_id, baseline in admission['members'].items():
        folder = ROOT / 'runs' / exp_id
        current = read(folder / 'checkpoint_head.json')
        item = {'head': current, 'baseline_epochs': baseline['completed_epochs'],
                'baseline_checkpoint_sha256': baseline['checkpoint_sha256'],
                'baseline_anchor_sha256': baseline['anchor_sha256'],
                'failure_sha256': sha(folder / 'failure.json'),
                'failure_matches_original': sha(folder / 'failure.json') == baseline['failure_sha256'],
                'config_matches_original': sha(folder / 'config.json') == baseline['config_sha256'],
                'anchor_matches_original': sha(folder / 'continuation_anchor.json') == baseline['anchor_sha256'],
                'migration_receipt_matches_original': sha(folder / 'migration_source.json') == baseline['migration_receipt_sha256'],
                'lineage_events': []}
        cursor, epoch = current['checkpoint_sha256'], current['completed_epochs']
        if epoch < baseline['completed_epochs'] or current['anchor_sha256'] != baseline['anchor_sha256']:
            raise ValueError('checkpoint precedes or differs from the original baseline: ' + exp_id)
        while cursor != baseline['checkpoint_sha256']:
            if epoch <= baseline['completed_epochs']:
                raise ValueError('checkpoint is not descended from the original baseline: ' + exp_id)
            event_path = folder / 'checkpoint_events' / (cursor[:16] + '.json')
            event = read(event_path)
            if (event.get('schema') != 'complete-epoch-transition-v1' or event.get('checkpoint_sha256') != cursor or
                    event.get('completed_epochs') != epoch or event.get('previous_epochs') != epoch - 1 or
                    event.get('anchor_sha256') != baseline['anchor_sha256']):
                raise ValueError('checkpoint lineage differs: ' + exp_id)
            item['lineage_events'].append({'sha256': sha(event_path), 'event': event})
            cursor, epoch = event['previous_checkpoint_sha256'], event['previous_epochs']
        item['lineage_reaches_original_baseline'] = epoch == baseline['completed_epochs']
        out['members'][exp_id] = item
except Exception as error:
    out['errors'].append({'type': type(error).__name__, 'message': str(error), 'traceback': traceback.format_exc()})
print('GRU_PROJECTION_INDEPENDENT_MONITOR_JSON ' + json.dumps(out, sort_keys=True), flush=True)

INDEPENDENT_REPAIR_MONITOR
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


def final_stage_metadata(runtime, record, case, row):
    """Read bounded final-stage records and committed heads; never load tensors."""
    result = {'group_outcomes': {}, 'physical_members': {}, 'aliases': {},
              'checkpoints_loaded': False, 'scientific_files_changed': False}
    for suffix in ('tune_branch_group', 'final_foundation_group', 'all_final_branches_group'):
        path = record / (suffix + '_outcome.json')
        if not path.exists():
            continue
        outcome = read(path)
        seal = outcome['seal']
        result['group_outcomes'][suffix] = {
            'path': str(path), 'sha256': sha(path),
            'seal': {key: seal[key] for key in ('group_id', 'member_ids', 'epochs',
                     'checkpoint_hashes', 'status', 'budget_final', 'evidence_sha256')},
            'members': {name: {key: value.get(key) for key in ('case', 'seed', 'method',
                'type', 'epochs', 'budget_final', 'best_epoch', 'checkpoint_sha256',
                'checkpoint_path', 'learning_rate', 'normalization_hash', 'whitening_hash',
                'initializer_hash', 'device_identity')} for name, value in outcome['members'].items()}}
    path = record / 'aliases_before_final_training.json'
    if path.exists():
        aliases = read(path)
        result['alias_record_sha256'] = sha(path)
        result['effective_configs_sha256_before_aliases'] = aliases['effective_configs_sha256']
        result['aliases'] = {name: target for name, target in aliases['aliases'].items()
                             if name.startswith(case + '__')}
    path = record / 'all_final_branches_group_configs.json'
    if not path.exists():
        return result
    configs = read(path)
    result['physical_configs_sha256'] = sha(path)
    for name, config in configs.items():
        assert name.startswith(case + '__') and name not in result['aliases']
        run = config['registration']
        effective = config['effective_config']
        folder = runtime / 'runs' / name
        item = {'method': run['method'], 'type': run['type'], 'seed': run['seed'],
                'learning_rate': effective['learning_rate'],
                'parent_run_id': effective['parent_run_id'], 'parent_hash': effective['parent_hash'],
                'folder_exists': folder.exists(), 'continuation_file_exists': (folder / 'continuation.pt').is_file()}
        config_path = folder / 'config.json'
        if config_path.exists():
            item['config_sha256'] = sha(config_path)
            item['frozen_config_matches'] = read(config_path) == config
        head_path = folder / 'checkpoint_head.json'
        if head_path.exists():
            head = read(head_path)
            assert 0 <= head['completed_epochs'] <= 200
            item['head'] = head
            event_path = folder / 'checkpoint_events' / (head['checkpoint_sha256'][:16] + '.json')
            if head['completed_epochs'] > 0 and event_path.exists():
                event = read(event_path)
                assert event['completed_epochs'] == head['completed_epochs']
                assert event['checkpoint_sha256'] == head['checkpoint_sha256']
                assert event['previous_epochs'] == head['completed_epochs'] - 1
                item['latest_complete_epoch_event'] = event
            anchor_path = folder / 'continuation_anchor.json'
            if anchor_path.exists():
                item['anchor_sha256'] = sha(anchor_path)
                item['anchor'] = read(anchor_path)
                item['head_anchor_matches'] = head.get('anchor_sha256') == item['anchor_sha256']
        step_path = folder / 'first_optimizer_step.json'
        if step_path.exists():
            step = read(step_path)
            item['first_optimizer_step'] = {key: step.get(key) for key in
                ('status', 'epoch', 'training_batch_size', 'method', 'device_identity')}
        failure_path = folder / 'failure.json'
        if failure_path.exists():
            row['failure_records'][name] = read(failure_path)
        result['physical_members'][name] = item
    result['physical_member_count'] = len(configs)
    result['logical_member_count'] = len(configs) + len(result['aliases'])
    result['complete200_physical_members'] = sum(
        value.get('head', {}).get('completed_epochs') == 200 for value in result['physical_members'].values())
    result['complete_member_epochs'] = sum(
        value.get('head', {}).get('completed_epochs', 0) for value in result['physical_members'].values())
    result['all_alias_targets_are_physical'] = all(target in configs for target in result['aliases'].values())
    return result


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
                     'scheduler_slice_end_' + job + '.json', 'startup_path_recovery_' + job + '.json',
                     'submission_context_repair.confirmed.json'):
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
        try:
            row['final_stage'] = final_stage_metadata(runtime, record, case, row)
        except Exception as error:
            row['final_stage_metadata_error'] = {'type': type(error).__name__, 'message': str(error)}
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
