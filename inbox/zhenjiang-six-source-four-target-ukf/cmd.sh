#!/usr/bin/env bash
# One authorized metadata-only query. No data/checkpoint contents are opened.
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
python -B -I - <<'PY'
import collections
import datetime
import hashlib
import json
import math
import pathlib
import re
import sqlite3
import subprocess
import sys

ROOT = pathlib.Path('/data1/home/sunyiq/zhenjiang_5s5t_stage_b_20260907_001')
JOB = '223517'
SEEDS = (17, 29, 43)
CONTRACT_SHA = '688ee2340954542b71955df35dd1f918450e0b01035f16b5bf353ce8ffbb798f'
AUTH_SHA = '39fc0920f7f13e9ec0aebd368e162fe026e08a3961efee35876758559632f9de'
PAID_SHA = 'feab3b9e38a9ce2c6f7e9e4d33c07f588c6361d315abcb8ecfd06665fa4a1a2e'
MANIFEST_SHA = 'ed5850dd8239a1fe36e3e6ce9b490b65133bd0fc8121809bb787167db75d68ec'
issues = []

def emit(section, value):
    print(json.dumps({'section': section, 'value': value}, ensure_ascii=False,
                     sort_keys=True, allow_nan=False), flush=True)

def now():
    return datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat()

def path_for(relative):
    relative = pathlib.PurePosixPath(relative)
    if relative.is_absolute() or '..' in relative.parts:
        raise RuntimeError('invalid relative metadata path')
    p = ROOT.joinpath(*relative.parts)
    if p.resolve() != p or ROOT not in p.parents:
        raise RuntimeError('symlink or path escape rejected: ' + str(p))
    return p

def document(relative, expected=None, required=False):
    p = path_for(relative)
    if not p.is_file():
        emit('missing_metadata', relative)
        if required:
            raise RuntimeError('required metadata absent: ' + relative)
        return None
    if p.suffix != '.json' or p.stat().st_size > 1048576:
        raise RuntimeError('metadata type or size rejected: ' + relative)
    raw = p.read_bytes()
    sha = hashlib.sha256(raw).hexdigest()
    if expected and sha != expected:
        raise RuntimeError('frozen metadata hash mismatch: ' + relative)
    value = json.loads(raw)
    emit('json_metadata', {'path': relative, 'bytes': len(raw), 'sha256': sha, 'document': value})
    return value

def command(args):
    started = now()
    try:
        result = subprocess.run(args, capture_output=True, text=True, timeout=30)
        value = {'argv': args, 'started_at_beijing': started, 'finished_at_beijing': now(),
                 'returncode': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr}
    except subprocess.TimeoutExpired:
        value = {'argv': args, 'started_at_beijing': started, 'finished_at_beijing': now(), 'error': 'timeout'}
    emit('scheduler', value)

def text_tail(relative, max_bytes=32768):
    p = path_for(relative)
    if not p.is_file():
        emit('missing_metadata', relative)
        return
    size = p.stat().st_size
    with p.open('rb') as handle:
        handle.seek(max(0, size - max_bytes))
        raw = handle.read(max_bytes)
    emit('text_log_tail', {'path': relative, 'size_bytes': size,
                          'modified_at_unix': p.stat().st_mtime, 'tail_only': size > max_bytes,
                          'text': raw.decode('utf-8', errors='replace')})

if not ROOT.is_dir() or ROOT.resolve() != ROOT:
    raise SystemExit('fixed calibration root absent or redirected')
emit('query_start', {'at_beijing': now(), 'job': JOB, 'root': str(ROOT), 'python': sys.executable,
                     'formal_data_contents_opened': False, 'checkpoint_contents_opened': False})
contract = document('contracts/stage_b_execution_contract.json', CONTRACT_SHA, True)
authorization = document('contracts/stage_b_data_authorization.json', AUTH_SHA, True)
document('contracts/paid_execution_authorization.json', PAID_SHA, True)
submission = document('evidence/submission/attempt_001/submission_receipt.json', required=True)
if (submission.get('status') != 'submitted' or str(submission.get('job_id')) != JOB
        or submission.get('sbatch_call_count') != 1):
    raise SystemExit('submission receipt does not bind exactly one job 223517')
manifest = document('bundle_manifest.json', MANIFEST_SHA, True)
source_identities = []
for row in manifest['source_files']:
    rel = row['relative_path']
    if not rel.startswith(('contracts/', 'run/scripts/', 'run/third_party/', 'run/docs/records/')):
        raise SystemExit('source manifest attempts to access a disallowed path')
    p = path_for(rel)
    if p.suffix not in ('.py', '.slurm', '.json', '.md'):
        raise SystemExit('source manifest attempts to access non-source content')
    raw = p.read_bytes()
    actual = hashlib.sha256(raw).hexdigest()
    same = len(raw) == row['byte_count'] and actual == row['sha256']
    source_identities.append({'path': rel, 'bytes': len(raw), 'sha256': actual, 'matches_frozen': same})
    if not same:
        issues.append('frozen_source_changed:' + rel)
emit('source_identity', source_identities)
if issues:
    emit('query_stop', issues)
    raise SystemExit(2)

command(['squeue', '-j', JOB, '-h', '-o', '%i|%j|%T|%M|%R|%Z'])
command(['sacct', '-X', '-n', '-P', '-S', '2026-09-07', '-j', JOB,
         '--format=JobID,JobName%40,State%30,ExitCode,Elapsed,Start,End,NodeList,WorkDir%180'])
command(['scontrol', 'show', 'job', JOB])
completions = {}
for seed in SEEDS:
    prefix = 'runs/stage_b/seed_' + str(seed)
    directory = path_for(prefix)
    if not directory.is_dir():
        emit('seed_directory_absent', seed)
        continue
    files = [{'name': p.name, 'size_bytes': p.stat().st_size}
             for p in sorted(directory.iterdir()) if p.is_file() and not p.is_symlink()]
    emit('seed_file_inventory_metadata_only', {'seed': seed, 'files': files})
    completion = document(prefix + '/completion.json')
    completions[seed] = completion
    document(prefix + '/failure.json')
    document(prefix + '/first_optimizer_update.json')
    epochs = []
    for p in sorted(directory.iterdir()):
        match = re.fullmatch(r'epoch_([0-9]{2})\.json', p.name)
        if match:
            if not 1 <= int(match.group(1)) <= 20:
                raise SystemExit('epoch outside frozen range')
            epochs.append(document(prefix + '/' + p.name))
    best_metric, best_epoch, stale = None, None, 0
    selection_errors = []
    for index, row in enumerate(epochs, 1):
        metric = row['selection_2022_575_cell_mae_m']
        if row['epoch'] != index or not math.isfinite(metric):
            selection_errors.append('epoch_order_or_finiteness:' + str(index))
        selected = best_metric is None or metric <= best_metric - 0.0001
        if selected != row['selected_as_best']:
            selection_errors.append('replacement_rule:' + str(index))
        if stale >= 4:
            selection_errors.append('continued_after_early_stop:' + str(index))
        if selected:
            best_metric, best_epoch, stale = metric, row['epoch'], 0
        else:
            stale += 1
    if completion:
        checks = {
            'status_and_seed': completion.get('status') == 'complete' and completion.get('seed') == seed,
            'execution_contract': completion.get('execution_contract_sha256') == CONTRACT_SHA,
            'data_authorization': completion.get('authorization_sha256') == AUTH_SHA,
            'normalization': completion.get('normalization_sha256') == contract['normalization_sha256'],
            'frozen_backbone_record': completion.get('frozen_backbone_parameter_count') == 20416
                and completion.get('frozen_backbone_all_tensors_bitwise_unchanged') is True,
            'best_epoch_and_metric': completion.get('best_epoch') == best_epoch
                and completion.get('best_selection_metric_m') == best_metric,
            'all_epoch_records_present': completion.get('epochs_completed') == len(epochs),
            'valid_termination_epoch': len(epochs) == 20 or stale >= 4,
            'best_and_last_checkpoint_identities_recorded':
                set(completion.get('checkpoint_files', {})) == {'best_checkpoint.pt', 'last_checkpoint.pt'},
        }
        for key, passed in checks.items():
            if not passed:
                issues.append('seed_' + str(seed) + ':' + key)
        emit('completion_record_audit', {'seed': seed, 'checks': checks,
             'checkpoint_bytes_and_tensor_values_not_rechecked': True})
    emit('selection_audit', {'seed': seed, 'epoch_count': len(epochs), 'best_epoch': best_epoch,
         'best_selection_metric_m': best_metric, 'errors': selection_errors})
    issues.extend('seed_' + str(seed) + ':' + item for item in selection_errors)
    batch_path = path_for(prefix + '/batch_updates.jsonl')
    if batch_path.is_file() and batch_path.stat().st_size <= 134217728:
        count, bad, zero_batches = 0, [], 0
        digest = hashlib.sha256()
        last = None
        with batch_path.open('rb') as handle:
            for line_number, raw in enumerate(handle, 1):
                digest.update(raw)
                try:
                    row = json.loads(raw)
                    gradients = [value for values in row['gradients'].values() for value in values]
                    if (row['gradient_scalar_count'] != 10 or len(gradients) != 10
                            or not row['gradients_finite'] or not all(math.isfinite(x) for x in gradients)
                            or not math.isfinite(row['loss_m'])):
                        bad.append(line_number)
                    zero_batches += int(row.get('zero_gradient_scalar_count', 0) > 0)
                    count += 1
                    last = row
                except (ValueError, KeyError, TypeError):
                    bad.append(line_number)
        emit('batch_log_audit', {'seed': seed, 'records': count, 'sha256': digest.hexdigest(),
             'bad_lines': bad, 'batches_with_any_zero_gradient': zero_batches,
             'zero_gradient_alone_is_not_failure': True, 'last_record': last})
        if bad:
            issues.append('seed_' + str(seed) + ':batch_log_requires_attention')
    else:
        emit('batch_log_unavailable_or_exceeds_metadata_limit', seed)

document('evidence/stage_b_job_attempt/attempt_001/completion.json')
text_tail('evidence/stage_b_job_attempt/attempt_001/failure.txt')
text_tail('logs/stage-b-' + JOB + '.out')
text_tail('logs/stage-b-' + JOB + '.err')
ledger_path = path_for('evidence/stage_b_formal_data_usage.sqlite3')
sidecars = [str(ledger_path) + suffix for suffix in ('-wal', '-shm', '-journal')
            if pathlib.Path(str(ledger_path) + suffix).exists()]
if not ledger_path.is_file() or sidecars:
    emit('ledger_not_opened', {'exists': ledger_path.is_file(), 'sidecars': sidecars})
    issues.append('ledger_readonly_snapshot_unavailable')
else:
    db = sqlite3.connect(ledger_path.as_uri() + '?mode=ro', uri=True, timeout=5)
    db.row_factory = sqlite3.Row
    db.execute('PRAGMA query_only=ON')
    db.execute('BEGIN')
    baselines = [dict(row) for row in db.execute('SELECT * FROM authorization_baselines ORDER BY authorization_id')]
    events = [dict(row) for row in db.execute('SELECT * FROM usage_events ORDER BY event_id')]
    db.close()
    emit('ledger_authorization_baselines', baselines)
    emit('ledger_events', events)
    allowed = {(row['path'], row['byte_offset'], row['byte_count']) for row in authorization['allowed_byte_ranges']}
    grouped = collections.defaultdict(list)
    ledger_errors = []
    for row in events:
        grouped[row['reservation_id']].append(row)
        if (row['authorization_id'] != authorization['authorization_id']
                or row['authorization_document_sha256'] != AUTH_SHA
                or row['purpose'] != contract['formal_purpose'] or row['time_partition'] != '2017-2022'
                or (row['path'], row['byte_offset'], row['byte_count']) not in allowed):
            ledger_errors.append('authorization_or_range:' + str(row['event_id']))
    counts = collections.Counter(row['event_type'] for row in events)
    if (len(baselines) != 1 or baselines[0]['authorization_id'] != authorization['authorization_id']
            or baselines[0]['authorization_document_sha256'] != AUTH_SHA
            or baselines[0]['previous_access_count_confirmed'] != 0
            or baselines[0]['maximum_read_count'] != 36):
        ledger_errors.append('authorization_baseline_mismatch')
    for reservation, rows in grouped.items():
        if [row['event_type'] for row in rows] != ['RESERVED', 'COMPLETED']:
            ledger_errors.append('incomplete_or_failed_pair:' + reservation)
            continue
        fields = ('path', 'byte_offset', 'byte_count', 'authorization_id', 'purpose', 'time_partition')
        if any(rows[0][key] != rows[1][key] for key in fields) or rows[1]['bytes_read'] != rows[1]['byte_count']:
            ledger_errors.append('inconsistent_pair:' + reservation)
    if counts['RESERVED'] > 36 or counts['COMPLETED'] > 36:
        ledger_errors.append('read_budget_exceeded')
    per_object = collections.Counter(row['path'] for row in events if row['event_type'] == 'COMPLETED')
    logical_sha = hashlib.sha256(json.dumps(events, ensure_ascii=False, sort_keys=True,
                                            separators=(',', ':'), allow_nan=False).encode()).hexdigest()
    prefix_checks = {}
    for seed, count in ((17, 12), (29, 24), (43, 36)):
        completion = completions.get(seed)
        if completion and len(events) >= count * 2:
            subset = events[:count * 2]
            subset_sha = hashlib.sha256(json.dumps(subset, ensure_ascii=False, sort_keys=True,
                                                   separators=(',', ':'), allow_nan=False).encode()).hexdigest()
            prefix_checks[str(seed)] = subset_sha == completion.get('ledger_snapshot_sha256')
            if not prefix_checks[str(seed)]:
                ledger_errors.append('completion_ledger_prefix:' + str(seed))
            own_block = events[(count - 12) * 2:count * 2]
            own_completed = [row for row in own_block if row['event_type'] == 'COMPLETED']
            own_objects = {(row['path'], row['byte_offset'], row['byte_count']) for row in own_completed}
            if len(own_completed) != 12 or own_objects != allowed:
                ledger_errors.append('seed_input_object_coverage:' + str(seed))
    emit('ledger_audit', {'counts': dict(counts), 'completed_bytes': sum(row['bytes_read'] for row in events
         if row['event_type'] == 'COMPLETED'), 'per_object_completed': dict(per_object),
         'logical_sha256': logical_sha, 'completion_prefix_matches': prefix_checks,
         'errors': ledger_errors, 'historical_prior_completed_reads': 48,
         'family_completed_reads': 48 + counts['COMPLETED']})
    issues.extend(ledger_errors)
command(['sacct', '-X', '-n', '-P', '-S', '2026-09-07', '-j', JOB,
         '--format=JobID,State%30,ExitCode,Elapsed,Start,End,NodeList'])
emit('query_end', {'at_beijing': now(), 'issues': issues,
     'parameter_values': 'not_verified_no_checkpoint_deserialization',
     'formal_data_contents_opened': False, 'checkpoint_contents_opened': False,
     'no_new_job_submitted': True, 'no_evaluation_performed': True})
PY
