#!/usr/bin/env bash
# Read-only joint observation of the original B array (224255), retry1 (224389, A800/hgpu8) and retry2 (A40/hgpu4).
# Extends observe_B_memory_retry_20260909.sh with the retry2 root; no job/evaluation call, no tensor read.
set -euo pipefail
python3 -I -B - <<'PY'
import base64
import datetime
import gzip
import hashlib
import json
import pathlib
import subprocess

FAMILY = pathlib.Path('/data1/home/sunyiq/kalmannet_wrr_model_selection_20260908')
R1 = FAMILY / 'resource_recovery_20260909/B_retry1'
R2 = FAMILY / 'resource_recovery_20260911/B_retry2'
EXP = 'repo/experiments/optimize_hyper_parameters/wrr_hp_extension_20260902'

def raw(path):
    assert path.is_file() and not path.is_symlink() and path.resolve() == path
    return path.read_bytes()

def snapshot(path):
    if not path.exists():
        return None
    data = raw(path)
    return {'path': str(path), 'sha256': hashlib.sha256(data).hexdigest(), 'content': json.loads(data)}

def observe_root(root, manifest_sha, slurm_sha, job_id, indices):
    assert root.resolve() == root and root.is_dir()
    manifest_raw = raw(root / 'RETRY_MANIFEST.json')
    assert hashlib.sha256(manifest_raw).hexdigest() == manifest_sha
    manifest = json.loads(manifest_raw)
    assert raw(root / 'array_job_id.txt').decode().strip() == job_id
    receipt = snapshot(root / 'SUBMISSION_RECEIPT.json')
    assert receipt['content']['job_id'] == job_id
    assert hashlib.sha256(raw(root / 'retry.slurm')).hexdigest() == slurm_sha
    source = json.loads(raw(root / 'STAGE_B_MANIFEST.json'))
    n = 0
    for rel, expected in {**source['static_files'], **manifest['extra_static_files']}.items():
        assert not rel.startswith('/') and '\\' not in rel and all(x not in ('', '.', '..') for x in rel.split('/'))
        assert hashlib.sha256(raw(root / rel)).hexdigest() == expected
        n += 1
    experiment = root / EXP
    combos = [json.loads(line) for line in raw(experiment / 'combos.jsonl').splitlines() if line.strip()]
    runs = []
    for i in indices:
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
        # slurm stdout/err tails (launcher gate messages land here before any claim)
        for kind in ('out', 'err'):
            p = root / 'logs' / ('slurm-%s_%d.%s' % (job_id, i, kind))
            if p.exists():
                item['slurm_%s_tail' % kind] = raw(p).decode(errors='replace')[-2000:]
        runs.append(item)
    return {'root': str(root), 'job_id': job_id, 'static_files_verified': n, 'submission_receipt': receipt, 'runs': runs,
            'throttle_update_record': snapshot(root / 'RETRY1_THROTTLE_UPDATE.json')}

r2_job = raw(R2 / 'array_job_id.txt').decode().strip()
queries = []
for argv in [
    ['squeue', '-r', '-j', '224255,224389,' + r2_job, '-h', '-o', '%i|%j|%P|%T|%M|%E|%R|%N'],
    ['sacct', '-j', '224255,224389,' + r2_job, '-X', '-n', '-P', '--format=JobID,JobIDRaw,State,ExitCode,Elapsed,Start,End,NodeList'],
    ['scontrol', 'show', 'job', '224389', '-o'],
    ['scontrol', 'show', 'job', r2_job, '-o'],
]:
    p = subprocess.run(argv, capture_output=True, text=True, timeout=45, check=False)
    queries.append({'command': argv, 'returncode': p.returncode, 'stdout': p.stdout, 'stderr': p.stderr})
    assert p.returncode == 0 and not p.stderr
retry1 = observe_root(R1, '567471e0b43fc924176d93e18d3c880b5f45db131378b1c46dc194a6e6002e2a',
                      '4c60d0e95e37cd521209e208b5427fd842ecbbedcc2681a5e360db5143f4f478', '224389', list(range(12)))
r2_manifest_sha = hashlib.sha256(raw(R2 / 'RETRY_MANIFEST.json')).hexdigest()
r2_slurm_sha = hashlib.sha256(raw(R2 / 'retry.slurm')).hexdigest()
retry2 = observe_root(R2, r2_manifest_sha, r2_slurm_sha, r2_job, [3, 4, 5, 9, 10, 11])
report = {'kind': 'READ_ONLY_B_RETRY1_RETRY2_OBSERVATION_NOT_ADMISSION', 'original_job_id': '224255',
          'observed_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'queries': queries, 'retry1': retry1, 'retry2': retry2,
          'retry2_manifest_sha256': r2_manifest_sha, 'retry2_slurm_sha256': r2_slurm_sha,
          'new_jobs_submitted': 0, 'jobs_modified_or_cancelled': 0, 'data_or_checkpoint_tensors_loaded': False}
blob = json.dumps(report, sort_keys=True, separators=(',', ':')).encode()
print('RETRY12_STATUS_GZIP_BASE64=' + base64.b64encode(gzip.compress(blob, mtime=0)).decode())
def summary(r):
    return {'job_id': r['job_id'], 'claimed': sum(x['claim'] is not None for x in r['runs']),
            'runs_with_completed_epochs': sum(x.get('completed_epochs', 0) > 0 for x in r['runs']),
            'failed_markers': sum(x.get('failed_marker_present', False) for x in r['runs']),
            'cell_metrics': sum(x.get('cell_metrics') is not None for x in r['runs']),
            'static_files_verified': r['static_files_verified']}
print('RETRY1_SUMMARY=' + json.dumps(summary(retry1)))
print('RETRY2_SUMMARY=' + json.dumps(summary(retry2)))
print('--- squeue'); print(queries[0]['stdout'].rstrip())
print('--- sacct (retry rows)'); print('\n'.join(l for l in queries[1]['stdout'].splitlines() if not l.startswith('224255')))
for r in retry2['runs']:
    print('--- retry2 index %d %s seed %d: claim=%s run_dirs=%d epochs=%s failed=%s' % (
        r['index'], r['combo']['run_id'], r['combo']['seed'], r['claim'] is not None, r['run_directory_count'],
        r.get('completed_epochs', 0), r.get('failed_marker_present', False)))
    for kind in ('err', 'out'):
        t = r.get('slurm_%s_tail' % kind)
        if t and t.strip():
            print('  slurm.%s tail: %s' % (kind, t.strip()[-600:].replace('\n', ' | ')))
PY
