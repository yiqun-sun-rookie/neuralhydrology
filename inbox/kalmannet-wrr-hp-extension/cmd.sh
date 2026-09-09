#!/usr/bin/env bash
# Read-only B startup observation; not terminal admission and never a submission.
set -euo pipefail
export EXPECTED_B_JOB_ID=224255
python3 -I -B - "${EXPECTED_B_JOB_ID:?expected submitted B job identity required}" <<'PY'
import base64
import collections
import datetime
import gzip
import hashlib
import json
import pathlib
import re
import subprocess
import sys

root = pathlib.Path('/data1/home/sunyiq/kalmannet_wrr_model_selection_20260908/stages/B')
assert root.is_dir() and not root.is_symlink() and root.resolve() == root
expected_job = sys.argv[1]
assert re.fullmatch(r'[0-9]+', expected_job)

def raw_file(path):
    assert path.is_file() and not path.is_symlink(), str(path)
    assert path.resolve().is_relative_to(root), str(path)
    return path.read_bytes()

def decode(raw):
    def pairs(items):
        result = {}
        for name, value in items:
            assert name not in result, 'Duplicate JSON key'
            result[name] = value
        return result
    return json.loads(raw, object_pairs_hook=pairs,
                      parse_constant=lambda value: {'nonfinite_observation_value': value})

def observe_json(path):
    if not path.exists():
        return None
    raw = raw_file(path)
    try:
        data = decode(raw)
    except (ValueError, AssertionError) as exc:
        data = {'observation_error': str(exc)}
    return {'path': str(path), 'bytes': len(raw),
            'sha256': hashlib.sha256(raw).hexdigest(), 'content': data}

def command(argv):
    response = subprocess.run(argv, capture_output=True, text=True,
                              check=False, timeout=45)
    return {'command': argv, 'returncode': response.returncode,
            'stdout': response.stdout, 'stderr': response.stderr}

job = raw_file(root / 'array_job_id.txt').decode().strip()
assert job == expected_job
manifest_raw = raw_file(root / 'STAGE_B_MANIFEST.json')
assert hashlib.sha256(manifest_raw).hexdigest() == 'c5f8d56480510729dd14d44cb00d5e703425ebdeb837b059b674998b425784b1'
manifest = decode(manifest_raw)
static_hashes = {}
for name, expected_hash in manifest['static_files'].items():
    assert name and not name.startswith('/') and '\\' not in name
    assert all(part not in ('', '.', '..') for part in name.split('/'))
    actual_hash = hashlib.sha256(raw_file(root / name)).hexdigest()
    assert actual_hash == expected_hash, name
    static_hashes[name] = actual_hash
receipts = {}
for name in ('DEPLOYMENT_RECEIPT.json', 'SUBMISSION_INTENT.json',
             'SUBMISSION_RESPONSE.json', 'SUBMISSION_RECEIPT.json',
             'CACHE_ENVIRONMENT_PREFLIGHT.json'):
    receipts[name] = observe_json(root / name)
    assert receipts[name] is not None
    assert 'observation_error' not in receipts[name]['content']
submission = receipts['SUBMISSION_RECEIPT.json']['content']
assert submission['status'] == 'SUBMITTED' and submission['stage'] == 'B'
assert submission['job_id'] == job and submission['stage_root'] == str(root)
exp = root / 'repo/experiments/optimize_hyper_parameters/wrr_hp_extension_20260902'
combos = [decode(line) for line in raw_file(exp / 'combos.jsonl').splitlines() if line.strip()]
assert len(combos) == 21 and [item['index'] for item in combos] == list(range(21))
assert [item['run_id'] for item in combos] == ['NGF-SELECT-20260908-B%02d' % (i + 1) for i in range(21)]
queue = command(['squeue', '-r', '-j', job, '-h', '-o', '%i|%T|%M|%R'])
accounting = command(['sacct', '-j', job, '-X', '-n', '-P',
                      '--format=JobID,JobIDRaw,State,ExitCode,Elapsed,Start,End,NodeList'])
state_counts = collections.Counter()
accounting_rows = []
for line in accounting['stdout'].splitlines():
    fields = line.split('|')
    if fields and re.fullmatch(re.escape(job) + r'_([0-9]+)', fields[0]):
        accounting_rows.append(fields)
        state_counts[fields[2]] += 1
audits = [observe_json(path) for path in exp.glob('audits/*_formal_*.json')]
runs = []
for combo in combos:
    index, seed = combo['index'], combo['seed']
    item = {'index': index, 'run_id': combo['run_id'], 'seed': seed, 'combo': combo,
            'claim': observe_json(root / 'claims' / ('index%04d.json' % index))}
    directories = list(exp.glob('runs/formal_seed%d_gpu/idx%04d_*' % (seed, index)))
    item['run_directory_count'] = len(directories)
    if len(directories) == 1:
        run = directories[0]
        assert run.is_dir() and not run.is_symlink() and run.resolve().is_relative_to(root)
        item['run_directory'] = str(run)
        epochs = run / 'results/epoch_log.jsonl'
        if epochs.is_file():
            raw = raw_file(epochs)
            complete = [line for line in raw.splitlines(keepends=True)
                        if line.strip() and line.endswith(b'\n')]
            item['epoch_log_bytes'] = len(raw)
            item['epoch_log_sha256'] = hashlib.sha256(raw).hexdigest()
            try:
                records = [decode(line) for line in complete]
                item['completed_epochs'] = len(records)
                if records:
                    item['first_epoch'], item['last_epoch'] = records[0], records[-1]
            except (ValueError, AssertionError) as exc:
                item['epoch_observation_error'] = str(exc)
        item['cell_metrics'] = observe_json(run / 'cell_metrics.json')
        item['failed_marker_present'] = (run / 'FAILED').is_file()
        if (run / 'error.txt').is_file():
            item['error_tail'] = raw_file(run / 'error.txt').decode(errors='replace')[-4000:]
    item['launcher_audits'] = [row for row in audits if row['content'].get('run_id') == combo['run_id']]
    runs.append(item)
baseline_raw = raw_file(root / 'REMOTE_BASELINE.json')
assert hashlib.sha256(baseline_raw).hexdigest() == '6314f746fce9f31d55687b35858736c4013bd5369e5b6a538bea155bd1b7c5ce'
report = {'kind': 'READ_ONLY_OBSERVATION_NOT_ADMISSION', 'stage': 'B', 'job_id': job,
          'observed_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'root': str(root), 'squeue': queue, 'sacct': accounting,
          'accounting_rows': accounting_rows, 'accounting_state_counts': dict(state_counts),
          'runs': runs, 'deployment_receipts': receipts, 'verified_static_files': static_hashes,
          'protected_files_freshly_rehashed_by_observer': False,
          'data_or_checkpoint_tensors_loaded': False,
          'training_or_evaluation_started_by_observer': False, 'new_jobs_submitted': 0}
blob = json.dumps(report, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()
print('STAGE_STATUS_GZIP_BASE64=' + base64.b64encode(gzip.compress(blob, mtime=0)).decode())
print('STATUS_SUMMARY=' + json.dumps({'job_id': job, 'stage': 'B',
    'accounting_state_counts': dict(state_counts),
    'claimed_runs': sum(row['claim'] is not None for row in runs),
    'runs_with_completed_epochs': sum(row.get('completed_epochs', 0) > 0 for row in runs),
    'failed_markers': sum(row.get('failed_marker_present', False) for row in runs),
    'static_files_verified': len(static_hashes), 'new_jobs_submitted': 0}))
PY
