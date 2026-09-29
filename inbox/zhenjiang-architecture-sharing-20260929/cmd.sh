#!/bin/bash
set -euo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -I -B - <<'ZJ_ARCH_AUDIT'
from __future__ import annotations

import base64
from io import BytesIO
import hashlib
import json
import math
from pathlib import Path, PurePosixPath
import subprocess
import tarfile

import torch

ROOT = Path('/data1/home/sunyiq/zhenjiang_architecture_sharing_20260929_001')
JOB = '231096'
REGISTRY_SHA = 'bbb07af90473ba1136043eceaa5a09bb6d085db172d7e37e1fe9a185e11179bf'
MANIFEST_SHA = '320a45562d1f2ced6b8baf165a777415596d2ecf1e7031c64711df2f5f02a06c'
PROTOCOL_SHA = '1c9e0e116fea48ebedef76670e82361b27b161889c361cba3897c795fa150378'
EXPECTED_RUNS = 114
EXPECTED_EPOCHS = 101


def sha(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def canonical(value) -> bytes:
    return json.dumps(value, sort_keys=True, ensure_ascii=False,
                      separators=(',', ':'), allow_nan=False).encode()


def raw_file(relative: str, limit: int = 200_000_000) -> bytes:
    name = PurePosixPath(relative)
    if name.is_absolute() or '..' in name.parts or '\\' in relative:
        raise ValueError('path outside exclusive root: ' + relative)
    path = ROOT.joinpath(*name.parts)
    if path.is_symlink() or not path.is_file():
        raise ValueError('missing or linked registered file: ' + relative)
    if path.stat().st_size > limit:
        raise ValueError('oversized registered file: ' + relative)
    return path.read_bytes()


def state_sha(state) -> str:
    digest = hashlib.sha256()
    for name, tensor in sorted(state.items()):
        array = tensor.detach().cpu().contiguous().numpy()
        digest.update(name.encode())
        digest.update(str(array.dtype).encode())
        digest.update(canonical(list(array.shape)))
        digest.update(array.tobytes())
    return digest.hexdigest()


submission_raw = raw_file('submission/submitted.json', 16_384)
submission = json.loads(submission_raw)
if (submission.get('job_id') != JOB or submission.get('status') != 'SUBMITTED_ONCE'
        or submission.get('planned_tasks') != EXPECTED_RUNS
        or submission.get('maximum_simultaneous_gpu_tasks') != 2
        or submission.get('root') != str(ROOT)):
    raise ValueError('submission identity differs')

account = subprocess.run(
    ['sacct', '-j', JOB, '-n', '-P',
     '--format=JobIDRaw,State,ExitCode,Elapsed,NodeList'],
    capture_output=True, text=True, timeout=30, check=False)
if account.returncode != 0 or len(account.stdout.encode()) > 1_000_000:
    raise ValueError('bounded scheduler accounting unavailable')
account_rows = {}
for line in account.stdout.splitlines():
    fields = line.split('|')
    if len(fields) >= 5:
        account_rows[fields[0].strip()] = {
            'state': fields[1].strip(), 'exit_code': fields[2].strip(),
            'elapsed': fields[3].strip(), 'node': fields[4].strip()}

registry_raw = raw_file('registry_frozen.json', 1_000_000)
manifest_raw = raw_file('reports/training_manifest.json', 1_000_000)
protocol_raw = raw_file('protocol.json', 100_000)
if sha(registry_raw) != REGISTRY_SHA or sha(manifest_raw) != MANIFEST_SHA or sha(protocol_raw) != PROTOCOL_SHA:
    raise ValueError('frozen registry, manifest or protocol hash differs')
registry = json.loads(registry_raw)
manifest = json.loads(manifest_raw)
protocol = json.loads(protocol_raw)
if (registry.get('status') != 'FROZEN_FOR_SINGLE_SUBMISSION'
        or registry.get('execution_ready') is not True
        or registry.get('mandatory_runs') != EXPECTED_RUNS
        or len(registry.get('runs', [])) != EXPECTED_RUNS
        or registry.get('epochs_per_run') != 100
        or registry.get('training_years') != [2017, 2018, 2019, 2020, 2021]
        or registry.get('selection_year') != 2022
        or registry.get('seeds') != [17, 29, 43]
        or registry.get('targets') != ['nanjing', 'zhenjiang', 'jiangyin', 'xuliujing']
        or registry.get('wusongkou_role') != 'input_only_not_target'
        or protocol.get('remote_root') != str(ROOT)
        or protocol.get('evaluation_years_read') is not False):
    raise ValueError('frozen scientific protocol differs')
for relative, spec in manifest.get('files', {}).items():
    value = raw_file(relative)
    if len(value) != spec['bytes'] or sha(value) != spec['sha256']:
        raise ValueError('sealed source changed: ' + relative)

expected_ids = [row['exp_id'] for row in registry['runs']]
if len(expected_ids) != len(set(expected_ids)):
    raise ValueError('duplicate experiment id in registry')
actual_dirs = sorted(path.name for path in (ROOT / 'runs').iterdir()
                     if path.is_dir() and not path.is_symlink())
if actual_dirs != sorted(expected_ids):
    raise ValueError('run directory set differs from frozen registry')

members = {
    'protocol.json': protocol_raw,
    'registry_frozen.json': registry_raw,
    'reports/training_manifest.json': manifest_raw,
    'submission/submitted.json': submission_raw,
    'deploy/deployment.json': raw_file('deploy/deployment.json', 32_768),
}
records_checked = checkpoints_checked = selected_state_checks = 0
attempt_job_ids = set()
selection_rows = []
curve_rows = []
parameter_rows = []
for index, row in enumerate(registry['runs']):
    exp_id = row['exp_id']
    if (row.get('required') is not True or row.get('status') != 'REGISTERED_NOT_STARTED'
            or row.get('epochs') != 100
            or row.get('information_arm') not in ('available', 'ideal_observed')
            or row.get('seed') not in (17, 29, 43)):
        raise ValueError('registered run identity differs: ' + exp_id)
    folder = 'runs/' + exp_id + '/'
    run_path = ROOT / 'runs' / exp_id
    if (run_path.is_symlink() or (run_path / 'failure.json').exists()
            or not (run_path / 'complete.json').is_file()):
        raise ValueError('run failure or missing completion: ' + exp_id)
    attempt_raw = raw_file(folder + 'attempt.json', 64_000)
    complete_raw = raw_file(folder + 'complete.json', 64_000)
    selection_raw = raw_file(folder + 'selection.json', 64_000)
    attempt = json.loads(attempt_raw)
    complete = json.loads(complete_raw)
    selection = json.loads(selection_raw)
    hardware = attempt.get('hardware', {})
    job_id = str(hardware.get('slurm_job_id', ''))
    if (attempt.get('status') != 'STARTED' or attempt.get('array_index') != index
            or attempt.get('experiment_id') != exp_id
            or attempt.get('registry_sha256') != REGISTRY_SHA
            or attempt.get('manifest_sha256') != MANIFEST_SHA
            or attempt.get('source_input_ledger') != registry.get('training_sources')
            or hardware.get('slurm_array_job_id') != JOB
            or hardware.get('slurm_array_task_id') != index
            or 'RTX 3090' not in hardware.get('gpu_name', '')
            or job_id in attempt_job_ids):
        raise ValueError('attempt identity, input ledger or hardware differs: ' + exp_id)
    attempt_job_ids.add(job_id)
    account_row = account_rows.get(job_id)
    if not account_row or account_row['state'].rstrip('+') != 'COMPLETED' or account_row['exit_code'] != '0:0':
        raise ValueError('array task accounting is not successful: ' + job_id)
    if (complete.get('status') != 'COMPLETE' or complete.get('array_index') != index
            or complete.get('experiment_id') != exp_id
            or complete.get('epoch_records') != EXPECTED_EPOCHS
            or complete.get('epoch_checkpoints') != EXPECTED_EPOCHS
            or complete.get('registry_sha256') != REGISTRY_SHA
            or complete.get('manifest_sha256') != MANIFEST_SHA
            or complete.get('initial_state_sha256') != attempt.get('initial_state_sha256')
            or complete.get('selection_sha256') != sha(selection_raw)
            or not math.isfinite(complete.get('elapsed_seconds', math.nan))):
        raise ValueError('completion receipt differs: ' + exp_id)
    if (selection.get('fixed_epoch') != 100
            or selection.get('fixed_epoch_checkpoint') != 'checkpoints/epoch_100.pt'
            or selection.get('selection_rule') != 'minimum_2022_mean_error_earliest_tie'):
        raise ValueError('selection policy differs: ' + exp_id)
    expected_json = {f'epoch_{epoch:03d}.json' for epoch in range(EXPECTED_EPOCHS)}
    expected_pt = {f'epoch_{epoch:03d}.pt' for epoch in range(EXPECTED_EPOCHS)}
    actual_json = {path.name for path in run_path.glob('epoch_*.json') if path.is_file() and not path.is_symlink()}
    actual_pt = {path.name for path in (run_path / 'checkpoints').glob('epoch_*.pt') if path.is_file() and not path.is_symlink()}
    if actual_json != expected_json or actual_pt != expected_pt:
        raise ValueError('exact epoch coverage differs: ' + exp_id)
    epoch_rows = []
    best_score = math.inf
    best_epoch = None
    for epoch in range(EXPECTED_EPOCHS):
        relative_json = folder + f'epoch_{epoch:03d}.json'
        record_raw = raw_file(relative_json, 64_000)
        record = json.loads(record_raw)
        checkpoint = record.get('checkpoint', {})
        relative_pt = folder + f'checkpoints/epoch_{epoch:03d}.pt'
        selection_error = record.get('selection_unweighted_error_m')
        if (record.get('experiment_id') != exp_id or record.get('epoch') != epoch
                or record.get('initial_state_sha256') != attempt.get('initial_state_sha256')
                or not isinstance(selection_error, (int, float))
                or not math.isfinite(selection_error) or selection_error < 0
                or checkpoint.get('relative_path') != relative_pt
                or not isinstance(checkpoint.get('bytes'), int) or checkpoint['bytes'] <= 0
                or not isinstance(checkpoint.get('sha256'), str) or len(checkpoint['sha256']) != 64
                or not isinstance(checkpoint.get('state_sha256'), str) or len(checkpoint['state_sha256']) != 64):
            raise ValueError('epoch identity or value differs: ' + relative_json)
        if epoch == 0:
            if record.get('train_weighted_error_m') is not None or record.get('shuffle_sha256') is not None:
                raise ValueError('epoch zero training fields differ: ' + exp_id)
        else:
            train_error = record.get('train_weighted_error_m')
            if (not isinstance(train_error, (int, float)) or not math.isfinite(train_error)
                    or train_error < 0 or not isinstance(record.get('shuffle_sha256'), str)
                    or len(record['shuffle_sha256']) != 64):
                raise ValueError('training epoch fields differ: ' + relative_json)
        if selection_error < best_score:
            best_score, best_epoch = selection_error, epoch
        if record.get('best_epoch_through_now') != best_epoch:
            raise ValueError('running earliest-minimum selection differs: ' + relative_json)
        weight_raw = raw_file(relative_pt, 20_000_000)
        if len(weight_raw) != checkpoint['bytes'] or sha(weight_raw) != checkpoint['sha256']:
            raise ValueError('checkpoint hash differs: ' + relative_pt)
        members[relative_json] = record_raw
        epoch_rows.append(record)
        records_checked += 1
        checkpoints_checked += 1
    if (selection.get('supplementary_selected_epoch') != best_epoch
            or selection.get('supplementary_selected_mae_m') != best_score):
        raise ValueError('final earliest-minimum selection differs: ' + exp_id)
    for epoch in sorted({100, best_epoch}):
        record = epoch_rows[epoch]
        relative_pt = record['checkpoint']['relative_path']
        state = torch.load(BytesIO(raw_file(relative_pt, 20_000_000)), map_location='cpu', weights_only=True)
        if not isinstance(state, dict) or not state or any(not torch.is_tensor(value) for value in state.values()):
            raise ValueError('selected checkpoint state differs: ' + relative_pt)
        count = sum(value.numel() for value in state.values())
        if count != row.get('allocated_trainable_parameters'):
            raise ValueError('checkpoint parameter count differs: ' + relative_pt)
        if state_sha(state) != record['checkpoint']['state_sha256']:
            raise ValueError('checkpoint tensor state hash differs: ' + relative_pt)
        selected_state_checks += 1
    selection_rows.append({
        'array_index': index, 'experiment_id': exp_id,
        'information_arm': row['information_arm'], 'architecture': row['architecture'],
        'hypothesis': row['hypothesis'], 'capacity_budget': row['capacity_budget'],
        'training_target': row['training_target'], 'seed': row['seed'],
        'fixed_epoch': 100, 'fixed_selection_error_m': epoch_rows[100]['selection_unweighted_error_m'],
        'supplementary_selected_epoch': best_epoch,
        'supplementary_selected_error_m': best_score,
        'epoch_100_checkpoint': epoch_rows[100]['checkpoint'],
        'supplementary_checkpoint': epoch_rows[best_epoch]['checkpoint']})
    curve_rows.append({
        'array_index': index, 'experiment_id': exp_id,
        'selection_error_m_by_epoch': [item['selection_unweighted_error_m'] for item in epoch_rows],
        'training_error_m_by_epoch': [item['train_weighted_error_m'] for item in epoch_rows]})
    parameter_rows.append({
        'array_index': index, 'experiment_id': exp_id,
        'allocated_trainable_parameters': row['allocated_trainable_parameters'],
        'effective_parameter_count_after_future_mask': row['effective_parameter_count_after_future_mask'],
        'state_or_hidden_width': row['state_or_hidden_width'],
        'output_dimensions': row['output_dimensions'],
        'model_implementation': row['model_implementation']})
    members[folder + 'attempt.json'] = attempt_raw
    members[folder + 'complete.json'] = complete_raw
    members[folder + 'selection.json'] = selection_raw

if (records_checked != EXPECTED_RUNS * EXPECTED_EPOCHS
        or checkpoints_checked != EXPECTED_RUNS * EXPECTED_EPOCHS
        or len(attempt_job_ids) != EXPECTED_RUNS):
    raise ValueError('independent run, epoch or task count differs')
if any((ROOT / 'runs').glob('*/failure.json')):
    raise ValueError('failure receipt exists')

selection_raw = canonical(selection_rows)
curves_raw = canonical(curve_rows)
parameters_raw = canonical(parameter_rows)
members['audit/selection_summary.json'] = selection_raw
members['audit/training_curves.json'] = curves_raw
members['audit/parameter_summary.json'] = parameters_raw
audit = {
    'status': 'COMPLETE_AUDITED', 'job_id': JOB, 'root': str(ROOT),
    'runs_checked': EXPECTED_RUNS, 'epoch_records_checked': records_checked,
    'checkpoint_hashes_checked': checkpoints_checked,
    'selected_state_checks': selected_state_checks,
    'source_files_checked': len(manifest['files']),
    'registry_sha256': sha(registry_raw), 'manifest_sha256': sha(manifest_raw),
    'protocol_sha256': sha(protocol_raw), 'submission_sha256': sha(submission_raw),
    'selection_summary_sha256': sha(selection_raw),
    'training_curves_sha256': sha(curves_raw),
    'parameter_summary_sha256': sha(parameters_raw),
    'task_job_ids_sha256': sha(canonical(sorted(attempt_job_ids))),
    'sacct_sha256': sha(account.stdout.encode()),
}
members['audit/remote_audit.json'] = canonical(audit)
payload = BytesIO()
with tarfile.open(fileobj=payload, mode='w:gz', compresslevel=9) as archive:
    for name, value in sorted(members.items()):
        info = tarfile.TarInfo(name)
        info.size = len(value)
        info.mode = 0o600
        archive.addfile(info, BytesIO(value))
bundle = payload.getvalue()
if len(bundle) > 4_500_000:
    raise ValueError('audited metadata bundle exceeds mailbox bound')
public = {**audit, 'bundle_bytes': len(bundle), 'bundle_sha256': sha(bundle),
          'bundle_members': len(members)}
print('AUDIT ' + json.dumps(public, sort_keys=True))
print('METADATA_BASE64 ' + base64.b64encode(bundle).decode())
ZJ_ARCH_AUDIT
