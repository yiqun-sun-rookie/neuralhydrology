#!/usr/bin/env bash
# Read only existing B logs for exact submitted array 224255. No scheduler mutation.
set -euo pipefail
python3 -I -B - <<'PY'
import base64
import datetime
import gzip
import hashlib
import json
import pathlib
import subprocess

root = pathlib.Path('/data1/home/sunyiq/kalmannet_wrr_model_selection_20260908/stages/B')
assert root.is_dir() and not root.is_symlink() and root.resolve() == root

def ordinary_bytes(path):
    assert path.is_file() and not path.is_symlink(), str(path)
    assert path.resolve().is_relative_to(root), str(path)
    return path.read_bytes()

assert ordinary_bytes(root / 'array_job_id.txt').decode().strip() == '224255'
manifest_raw = ordinary_bytes(root / 'STAGE_B_MANIFEST.json')
assert hashlib.sha256(manifest_raw).hexdigest() == 'c5f8d56480510729dd14d44cb00d5e703425ebdeb837b059b674998b425784b1'
manifest = json.loads(manifest_raw)
assert hashlib.sha256(ordinary_bytes(root / 'hpc_array.slurm')).hexdigest() == manifest['static_files']['hpc_array.slurm']
exp = root / 'repo/experiments/optimize_hyper_parameters/wrr_hp_extension_20260902'
combo_raw = ordinary_bytes(exp / 'combos.jsonl')
assert hashlib.sha256(combo_raw).hexdigest() == manifest['static_files']['repo/experiments/optimize_hyper_parameters/wrr_hp_extension_20260902/combos.jsonl']
combos = [json.loads(line) for line in combo_raw.splitlines()]
assert len(combos) == 21 and [c['index'] for c in combos] == list(range(21))

def snapshot(path):
    assert not path.is_symlink(), str(path)
    if not path.exists():
        return None
    data = ordinary_bytes(path)
    assert len(data) <= 2 * 1024 * 1024, 'Early-start log exceeded read-only diagnostic bound'
    return {'path': str(path), 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest(),
            'raw_base64': base64.b64encode(data).decode()}

def query(argv):
    result = subprocess.run(argv, capture_output=True, text=True, timeout=45, check=False)
    return {'command': argv, 'returncode': result.returncode,
            'stdout': result.stdout, 'stderr': result.stderr}

started = datetime.datetime.now(datetime.timezone.utc).isoformat()
queue = query(['squeue', '-r', '-j', '224255', '-h', '-o', '%i|%T|%M|%R'])
accounting = query(['sacct', '-j', '224255', '-X', '-n', '-P',
                    '--format=JobID,JobIDRaw,State,ExitCode,Elapsed,Start,End,NodeList'])
runs = []
for combo in combos:
    index = combo['index']
    run_id = 'NGF-SELECT-20260908-B%02d' % (index + 1)
    assert combo['run_id'] == run_id and combo['stage'] == 'B'
    files = {'slurm_stdout': snapshot(root / 'logs' / ('slurm-224255_%d.out' % index)),
             'slurm_stderr': snapshot(root / 'logs' / ('slurm-224255_%d.err' % index)),
             'launcher_stdout': snapshot(exp / 'logs' / (run_id + '_formal.stdout.log'))}
    directories = list(exp.glob('runs/formal_seed%d_gpu/idx%04d_*' % (combo['seed'], index)))
    assert len(directories) <= 1
    if directories:
        run = directories[0]
        assert run.is_dir() and not run.is_symlink() and run.resolve().is_relative_to(root)
        for label, relative in [('error', 'error.txt'), ('failed_marker', 'FAILED'),
                                ('config', 'config_used.yaml'), ('epoch_log', 'results/epoch_log.jsonl')]:
            files[label] = snapshot(run / relative)
    runs.append({'index': index, 'run_id': run_id, 'combo': combo,
                 'run_directory_count': len(directories), 'files': files})
report = {'kind': 'READ_ONLY_B_TRAINING_LOG_DIAGNOSTIC', 'job_id': '224255', 'stage': 'B',
          'root': str(root), 'started_at_utc': started,
          'finished_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'squeue': queue, 'sacct': accounting, 'runs': runs,
          'source_or_data_tensors_executed_or_loaded': False, 'new_jobs_submitted': 0,
          'existing_jobs_changed': False, 'files_written_on_remote': 0}
blob = json.dumps(report, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()
print('B_TRAINING_DIAGNOSTIC_GZIP_BASE64=' + base64.b64encode(gzip.compress(blob, mtime=0)).decode(), flush=True)
print('DIAGNOSTIC_SUMMARY=' + json.dumps({'job_id': '224255', 'captured_runs': len(runs),
    'captured_files': sum(v is not None for r in runs for v in r['files'].values()),
    'squeue_returncode': queue['returncode'], 'sacct_returncode': accounting['returncode'],
    'new_jobs_submitted': 0}), flush=True)
assert all(q['returncode'] == 0 and not q['stderr'] for q in (queue, accounting))
PY
