#!/usr/bin/env bash
set -eo pipefail
python3 - <<'A40_SAVED_LOG'
import base64,json
namespace={'__name__':'saved_log_reader'}
exec(compile(base64.b64decode('IiIiUmV0dXJuIHR3byBwaW5uZWQsIGFscmVhZHkgcHJlc2VydmVkIHRleHQgYXJ0aWZhY3RzOyBubyBzb3VyY2Ugd3JpdGVzIG9yIGNvbXB1dGUuIiIiCmltcG9ydCBiYXNlNjQKZnJvbSBkYXRldGltZSBpbXBvcnQgZGF0ZXRpbWUsIHRpbWV6b25lCmltcG9ydCBoYXNobGliCmltcG9ydCBqc29uCmZyb20gcGF0aGxpYiBpbXBvcnQgUGF0aAppbXBvcnQgc3RhdAoKTUFSS0VSID0gIkdSVV9BNDBfU0FWRURfRkFJTFVSRV9MT0dfSlNPTiIKCgpkZWYgY2hlY2tlZF9ieXRlcyhwYXRoLCBleHBlY3RlZCwgbWF4aW11bSk6CiAgICBwYXRoID0gUGF0aChwYXRoKQogICAgYmVmb3JlID0gcGF0aC5sc3RhdCgpCiAgICBhc3NlcnQgcGF0aC5pc19hYnNvbHV0ZSgpIGFuZCBwYXRoLnJlc29sdmUoKSA9PSBwYXRoIGFuZCBzdGF0LlNfSVNSRUcoYmVmb3JlLnN0X21vZGUpCiAgICBhc3NlcnQgMCA8IGJlZm9yZS5zdF9zaXplIDw9IG1heGltdW0KICAgIHJhdyA9IHBhdGgucmVhZF9ieXRlcygpCiAgICBhZnRlciA9IHBhdGgubHN0YXQoKQogICAgYXNzZXJ0IChiZWZvcmUuc3RfaW5vLCBiZWZvcmUuc3Rfc2l6ZSwgYmVmb3JlLnN0X210aW1lX25zLCBiZWZvcmUuc3RfY3RpbWVfbnMpID09IChhZnRlci5zdF9pbm8sIGFmdGVyLnN0X3NpemUsIGFmdGVyLnN0X210aW1lX25zLCBhZnRlci5zdF9jdGltZV9ucykKICAgIGFzc2VydCBoYXNobGliLnNoYTI1NihyYXcpLmhleGRpZ2VzdCgpID09IGV4cGVjdGVkCiAgICByZXR1cm4gcmF3CgoKZGVmIG1haW4ocGxhbik6CiAgICBkaXJlY3RvcnkgPSBQYXRoKHBsYW5bImV2aWRlbmNlX2RpciJdKQogICAgbWFuaWZlc3QgPSBjaGVja2VkX2J5dGVzKGRpcmVjdG9yeSAvICJFVklERU5DRV9NQU5JRkVTVC5qc29uIiwgcGxhblsibWFuaWZlc3Rfc2hhMjU2Il0sIDEwNDg1NzYpCiAgICByZWNvcmRzID0ganNvbi5sb2FkcyhtYW5pZmVzdCkKICAgIGFzc2VydCByZWNvcmRzWyJzY2hlbWEiXSA9PSAiMDAzLUE0MC1mYWlsdXJlLXByZXNlcnZhdGlvbi12MSIKICAgIGFzc2VydCBsZW4ocmVjb3Jkc1siZmlsZXMiXSkgPT0gcGxhblsiZXZpZGVuY2VfZmlsZV9jb3VudCJdCiAgICBpdGVtID0gcmVjb3Jkc1siZmlsZXMiXVtwbGFuWyJsb2dfcmVsYXRpdmVfcGF0aCJdXQogICAgYXNzZXJ0IGl0ZW1bInNvdXJjZSJdID09IHBsYW5bIm9yaWdpbmFsX2xvZ19zb3VyY2UiXQogICAgYXNzZXJ0IGl0ZW1bInNoYTI1NiJdID09IHBsYW5bImxvZ19zaGEyNTYiXSBhbmQgaXRlbVsic2l6ZSJdID09IHBsYW5bImxvZ19zaXplIl0KICAgIGFzc2VydCAicmV1c2VkX2Zyb20iIG5vdCBpbiBpdGVtCiAgICBwYXRoID0gZGlyZWN0b3J5IC8gcGxhblsibG9nX3JlbGF0aXZlX3BhdGgiXQogICAgYXNzZXJ0IGRpcmVjdG9yeSBpbiBwYXRoLnBhcmVudHMgYW5kICIuLiIgbm90IGluIHBhdGgucGFydHMKICAgIGxvZyA9IGNoZWNrZWRfYnl0ZXMocGF0aCwgcGxhblsibG9nX3NoYTI1NiJdLCBwbGFuWyJsb2dfc2l6ZSJdKQogICAgYXNzZXJ0IGxlbihsb2cpID09IHBsYW5bImxvZ19zaXplIl0KICAgIHByaW50KE1BUktFUiArICIgIiArIGpzb24uZHVtcHMoewogICAgICAgICJzY2hlbWEiOiAiMDAzLUE0MC1zYXZlZC1mYWlsdXJlLWxvZy12MSIsICJzdGF0dXMiOiAicGlubmVkX2V4aXN0aW5nX2xvZ19hbmRfbWFuaWZlc3RfcmVhZCIsCiAgICAgICAgImNoZWNrZWRfYXRfdXRjIjogZGF0ZXRpbWUubm93KHRpbWV6b25lLnV0YykuaXNvZm9ybWF0KCksICJqb2JfaWQiOiBwbGFuWyJqb2JfaWQiXSwKICAgICAgICAicHJlc2VydmF0aW9uX3NlcXVlbmNlIjogcGxhblsicHJlc2VydmF0aW9uX3NlcXVlbmNlIl0sICJldmlkZW5jZV9kaXIiOiBzdHIoZGlyZWN0b3J5KSwKICAgICAgICAibWFuaWZlc3Rfc2hhMjU2IjogcGxhblsibWFuaWZlc3Rfc2hhMjU2Il0sICJsb2dfc2hhMjU2IjogcGxhblsibG9nX3NoYTI1NiJdLAogICAgICAgICJtYW5pZmVzdF9iYXNlNjQiOiBiYXNlNjQuYjY0ZW5jb2RlKG1hbmlmZXN0KS5kZWNvZGUoImFzY2lpIiksCiAgICAgICAgImxvZ19iYXNlNjQiOiBiYXNlNjQuYjY0ZW5jb2RlKGxvZykuZGVjb2RlKCJhc2NpaSIpLAogICAgICAgICJsb2dfc2l6ZSI6IGxlbihsb2cpLCAic291cmNlX2ZpbGVzX3JlYWQiOiAwLCAidGVuc29yX2ZpbGVzX2xvYWRlZCI6IEZhbHNlLAogICAgICAgICJyZW1vdGVfZmlsZXNfd3JpdHRlbiI6IDAsICJzY2hlZHVsZXJfbXV0YXRpb25zIjogMCwgIm9wdGltaXplcl9zdGVwcyI6IDAsCiAgICB9KSwgZmx1c2g9VHJ1ZSkK'),'read_saved_log.py','exec'),namespace)
namespace['main'](json.loads(base64.b64decode('ewogICJldmlkZW5jZV9kaXIiOiAiL2RhdGExL2hvbWUvc3VueWlxL3poZW5qaWFuZ19jb21wbGV0ZV9jb21wYXJpc29uX2ZpeGVkMjAwXzIwMjYxMDE5XzAwMy9zcXJ0X2dydV9yZWNvdmVyeS9yZWNvcmRzL2V4cGxpY2l0X2dydV9faGlzdG9yaWNhbF9jYXBhY2l0eS9yZXBhaXJzL0E0MF9hZnRlcl8yNTgxNjZfZmFpbHVyZV9wcmVzZXJ2YXRpb25fOTc2XzAwMSIsCiAgImV2aWRlbmNlX2ZpbGVfY291bnQiOiA2ODgsCiAgImZhaWxlZF9vd25lcl9rZXkiOiAiZXhwbGljaXRfZ3J1X19oaXN0b3JpY2FsX2NhcGFjaXR5L0E0MF9yZXN1bWVfYWZ0ZXJfMjU3Mjg0IiwKICAiam9iX2lkIjogIjI1ODE2NiIsCiAgImxvZ19yZWxhdGl2ZV9wYXRoIjogInNvdXJjZS9sb2dzL3pqMDAzX2V4cGxpY2l0X2dydV9faGlzdG9yaWNhbF9jYXBhY2l0eV8yNTgxNjYub3V0IiwKICAibG9nX3NoYTI1NiI6ICI3ZmJlZmNmZDFiMWI4ZjNhYjkwOTc3MmJhMGYxMjYxMzdiZmFmZGYzNzVlOGY0MWQ2ODFhZWYxNGNmMmEyNDQwIiwKICAibG9nX3NpemUiOiAxMzEyMzIsCiAgIm1hbmlmZXN0X3NoYTI1NiI6ICJlZjUwNzNjNDQ2ZTA5NTQ5MTUzMTkyZDgyYzc2NzIxMzcxYTMwOWRhYmMxMmRmNjAwZmY3MDAwZmZkYWRmZTNlIiwKICAib3JpZ2luYWxfbG9nX3NvdXJjZSI6ICIvZGF0YTEvaG9tZS9zdW55aXEvemhlbmppYW5nX2NvbXBsZXRlX2NvbXBhcmlzb25fZml4ZWQyMDBfMjAyNjEwMTlfMDAzL3NxcnRfZ3J1X3JlY292ZXJ5L2xvZ3MvemowMDNfZXhwbGljaXRfZ3J1X19oaXN0b3JpY2FsX2NhcGFjaXR5XzI1ODE2Ni5vdXQiLAogICJwcmVzZXJ2YXRpb25fa2V5IjogImV4cGxpY2l0X2dydV9faGlzdG9yaWNhbF9jYXBhY2l0eS9BNDBfYWZ0ZXJfMjU4MTY2X2ZhaWx1cmVfOTc2IiwKICAicHJlc2VydmF0aW9uX3Byb29mIjogIkc6XFxnaXRodWJcXHB5Y2hhcm1cXHByb2plY3RzXFx6aGVuamlhbmdfY29tcGxldGVfY29tcGFyaXNvbl8yMDI2MTAwNl8wMDJcXHJlc3VsdHNcXGZpeGVkMjAwXzAwM19hY3RpdmF0aW9uXzIwMjYxMDIwXzAwMVxccHJvamVjdGlvbl9yZXBhaXJfMjAyNjExMDVfMDAxXFxwYXJhbGxlbF9jb250aW51YXRpb25fMjAyNjExMDZfMDAxXFxBNDBfYWZ0ZXJfMjU4MTY2X2ZhaWx1cmVfOTc2XzAwMVxcRkFJTFVSRV9GVUxMX1NUQVRFU19QUkVTRVJWRUQuanNvbiIsCiAgInByZXNlcnZhdGlvbl9wcm9vZl9zaGEyNTYiOiAiY2M3ZWVhNjg2ZmQ2ZWUxZmIzNmEzOTcxZDljMDYyNDhjODFhODIwOGE2NDhlMGNmNmZkNmIwM2FjMTY4ZDNhYiIsCiAgInByZXNlcnZhdGlvbl9zZXF1ZW5jZSI6IDk3NywKICAicHVycG9zZSI6ICJSZXRyaWV2ZSB0aGUgZXhpc3RpbmcgY29tcGxldGUgc2F2ZWQgbG9nIGFuZCBtYW5pZmVzdCBiZWNhdXNlIG5hdGl2ZTk3NyByZXR1cm5lZCBvbmx5IHRoZSBsYXN0NjU1MzYgb2YxMzEyMzIgbG9nIGJ5dGVzOyBkaWFnbm9zZSBzYXZlZCBhcnRpZmFjdHMgd2l0aG91dCByZXBsYXkgb3Igc3RhdGUgbXV0YXRpb24uIiwKICAic2NoZW1hIjogIjAwMy1BNDAtZnVsbC1zYXZlZC1mYWlsdXJlLWxvZy1wbGFuLXYxIgp9Cg==')))
A40_SAVED_LOG
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
