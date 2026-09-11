#!/usr/bin/env bash
# Read-only observation of the exact original B array and authorized A800 retry.
set -euo pipefail
python3 -I -B - <<'PY'
import base64
import datetime
import gzip
import hashlib
import json
import pathlib
import subprocess

root = pathlib.Path('/data1/home/sunyiq/kalmannet_wrr_model_selection_20260908/resource_recovery_20260909/B_retry1')
assert root.resolve() == root and root.is_dir()

def raw(path):
    assert path.is_file() and not path.is_symlink() and path.resolve() == path
    return path.read_bytes()

def snapshot(path):
    if not path.exists():
        return None
    data = raw(path)
    return {'path': str(path), 'sha256': hashlib.sha256(data).hexdigest(),
            'content': json.loads(data)}

manifest_raw = raw(root / 'RETRY_MANIFEST.json')
assert hashlib.sha256(manifest_raw).hexdigest() == '567471e0b43fc924176d93e18d3c880b5f45db131378b1c46dc194a6e6002e2a'
manifest = json.loads(manifest_raw)
assert raw(root / 'array_job_id.txt').decode().strip() == '224389'
receipt = snapshot(root / 'SUBMISSION_RECEIPT.json')
assert receipt['content']['job_id'] == '224389'
assert hashlib.sha256(raw(root / 'retry.slurm')).hexdigest() == '4c60d0e95e37cd521209e208b5427fd842ecbbedcc2681a5e360db5143f4f478'
source = json.loads(raw(root / 'STAGE_B_MANIFEST.json'))
for rel, expected in {**source['static_files'], **manifest['extra_static_files']}.items():
    assert not rel.startswith('/') and '\\' not in rel and all(x not in ('', '.', '..') for x in rel.split('/'))
    assert hashlib.sha256(raw(root / rel)).hexdigest() == expected
queries = []
for argv in [
    ['squeue', '-r', '-j', '224255,224389', '-h', '-o', '%i|%j|%P|%T|%M|%E|%R'],
    ['sacct', '-j', '224255,224389', '-X', '-n', '-P', '--format=JobID,JobIDRaw,State,ExitCode,Elapsed,Start,End,NodeList'],
]:
    p = subprocess.run(argv, capture_output=True, text=True, timeout=45, check=False)
    queries.append({'command': argv, 'returncode': p.returncode, 'stdout': p.stdout, 'stderr': p.stderr})
    assert p.returncode == 0 and not p.stderr
experiment = root / 'repo/experiments/optimize_hyper_parameters/wrr_hp_extension_20260902'
combos = [json.loads(line) for line in raw(experiment / 'combos.jsonl').splitlines() if line.strip()]
runs = []
for i in range(12):
    c = combos[i]
    item = {'index': i, 'combo': c, 'claim': snapshot(root / 'claims' / ('index%04d.json' % i))}
    directories = list(experiment.glob('runs/formal_seed%d_gpu/idx%04d_*' % (c['seed'], i)))
    assert len(directories) <= 1
    item['run_directory_count'] = len(directories)
    item['audits'] = [snapshot(p) for p in (experiment / 'audits').glob(c['run_id'] + '_formal_*.json')]
    if directories:
        run = directories[0]
        item['cell_metrics'] = snapshot(run / 'cell_metrics.json')
        item['failed_marker_present'] = (run / 'FAILED').is_file()
        epochs = run / 'results/epoch_log.jsonl'
        if epochs.exists():
            data = raw(epochs)
            records = [json.loads(line) for line in data.splitlines(keepends=True) if line.endswith(b'\n') and line.strip()]
            item['completed_epochs'] = len(records)
            item['last_epoch'] = records[-1] if records else None
            item['epoch_log_sha256'] = hashlib.sha256(data).hexdigest()
        if (run / 'error.txt').exists():
            item['error_tail'] = raw(run / 'error.txt').decode(errors='replace')[-4000:]
    runs.append(item)
report = {'kind': 'READ_ONLY_B_AND_A800_RETRY_OBSERVATION_NOT_ADMISSION', 'original_job_id': '224255',
          'retry_job_id': '224389', 'observed_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'queries': queries, 'retry_runs': runs, 'submission_receipt': receipt,
          'static_files_verified': 69, 'new_jobs_submitted': 0, 'data_or_checkpoint_tensors_loaded': False}
blob = json.dumps(report, sort_keys=True, separators=(',', ':')).encode()
print('MEMORY_RETRY_STATUS_GZIP_BASE64=' + base64.b64encode(gzip.compress(blob, mtime=0)).decode())
print('MEMORY_RETRY_STATUS_SUMMARY=' + json.dumps({'retry_job_id': '224389',
      'claimed': sum(r['claim'] is not None for r in runs),
      'runs_with_completed_epochs': sum(r.get('completed_epochs', 0) > 0 for r in runs),
      'failed_markers': sum(r.get('failed_marker_present', False) for r in runs)}))
PY
