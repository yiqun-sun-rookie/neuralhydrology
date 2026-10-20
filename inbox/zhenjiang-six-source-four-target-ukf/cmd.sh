#!/usr/bin/env bash
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
export OMP_NUM_THREADS=2
python -B - <<'HANDOFF_003'
"""Handoff one old LSTM writer, preserve its state, prepare fixed-200 candidates.

Usage on HPC: python -B handoff.py
Writes a new isolated handoff root, reads the existing RTX3090 allocation,
stops only job 236707, and submits one two-minute A40 identity probe. Does not
call a training/evaluation entry point, alter scientific sources, or refit data.
"""
import copy
import datetime
import gc
import hashlib
import importlib
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

import torch

BASE = Path('/data1/home/sunyiq')
DEST = BASE / 'zhenjiang_fixed200_003_handoff_20261020_001'
ORIGINAL = BASE / 'zhenjiang_complete_comparison_20261006_002'
OLD = BASE / 'zhenjiang_fixed200_003_candidates_20261019_002'
ARCHIVE = BASE / 'zhenjiang_fixed200_003_sources_20261019_001'
PRE = BASE / 'zhenjiang_fixed200_003_boundary_20261020_001'
GRU_PRE = BASE / 'zhenjiang_fixed200_003_boundary_20261020_002'
CASE = 'legacy_lstm__historical_capacity'
GRU = 'explicit_gru__historical_capacity'
JOB = '236707'
SLURM = Path('/usr/local/globle/softs/slurm/19.05.4.1/bin')


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def stable(path):
    for _ in range(3):
        before = path.stat()
        raw = path.read_bytes()
        after = path.stat()
        if (before.st_size, before.st_mtime_ns) == (after.st_size, after.st_mtime_ns) and len(raw) == after.st_size:
            return raw
    raise ValueError('concurrent source replacement: ' + str(path))


def read(path):
    return json.loads(stable(path))


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('x') as handle:
        json.dump(value, handle, sort_keys=True, indent=2, allow_nan=False)
        handle.write('\n')


def query(command, timeout=40, checked=True):
    result = subprocess.run(list(map(str, command)), capture_output=True, text=True, timeout=timeout)
    item = {'command': list(map(str, command)), 'returncode': result.returncode,
            'stdout': result.stdout, 'stderr': result.stderr, 'at_utc': now()}
    if checked and result.returncode:
        raise RuntimeError(json.dumps(item))
    return item


def queue():
    return query([SLURM / 'squeue', '-h', '-u', 'sunyiq', '-o', '%i|%j|%T|%Z|%o'])


PROBE = r'''"""Read one real allocated GPU identity; no model or data access."""
import argparse,datetime,hashlib,json,os,sys
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--case',required=True);p.add_argument('--runtime',required=True)
p.add_argument('--expected',required=True);p.add_argument('--output',required=True);a=p.parse_args()
sys.path.insert(0,a.runtime)
from src.execution import device_identity
from src.scheduler import code_identity
expected=json.loads(Path(a.expected).read_bytes());actual=device_identity('cuda:0')
result={'schema':'fixed200-actual-gpu-identity-v1','case':a.case,'actual_device_identity':actual,
        'expected_device_identity':expected,'matches':actual==expected,'code_hash':code_identity(a.runtime),
        'job_id':os.environ.get('SLURM_JOB_ID'),'node':os.environ.get('SLURMD_NODENAME'),
        'cuda_visible_devices':os.environ.get('CUDA_VISIBLE_DEVICES'),'training_steps':0,
        'at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat()}
with Path(a.output).open('x') as f:json.dump(result,f,sort_keys=True,indent=2);f.write('\n')
print(json.dumps(result),flush=True)
if not result['matches']:sys.exit(3)
'''


assert not DEST.exists(), 'handoff root exists; read its receipt instead of replaying'
DEST.mkdir()
(DEST / 'hardware').mkdir()
(DEST / 'logs').mkdir()
torch.set_num_threads(2)
report = {'schema': 'fixed200-case-handoff-v1', 'started_utc': now(), 'case': CASE,
          'root': str(DEST), 'source_root': str(ORIGINAL), 'previous_job': JOB,
          'activated': False, 'training_steps': 0, 'tide_refits': 0,
          'evaluation_values_read': False, 'source_files_written': False,
          'members': [], 'errors': [], 'old_job_stopped': False}
try:
    prior_raw = stable(PRE / 'boundary_report.json')
    gru_raw = stable(GRU_PRE / 'boundary_report.json')
    assert sha(prior_raw) == '25f94549e0856403a48ddf46bb0c4b0897fc9eec5e693d7417c8bef717f858ec'
    assert sha(gru_raw) == '8daba09828c2c1fe7679a0564ada9efc27aa1f094036c76276c02fd28e76b5f6'
    prior, gru_prior = json.loads(prior_raw), json.loads(gru_raw)
    report['reused_preflight_reports'] = {'687': sha(prior_raw), '688': sha(gru_raw)}
    runtime = DEST / 'runtimes/base'
    gru_runtime = DEST / 'runtimes/sqrt_gru_recovery'
    shutil.copytree(PRE / 'runtimes/base', runtime)
    shutil.copytree(GRU_PRE / 'runtimes/sqrt_gru_recovery', gru_runtime)
    sys.path.insert(0, str(runtime))
    cp = importlib.import_module('src.continuation')
    scheduler = importlib.import_module('src.scheduler')
    training = importlib.import_module('src.training')
    models = importlib.import_module('src.models')
    estimators = importlib.import_module('src.state_estimators')
    filters = importlib.import_module('src.differentiable_filter')
    assert scheduler.code_identity(runtime) == prior['cases'][CASE]['code_hash']
    assert scheduler.code_identity(ORIGINAL) == prior['cases'][CASE]['original_code_hash']
    assert scheduler.code_identity(gru_runtime) == gru_prior['cases'][GRU]['code_hash']
    assert not read(runtime / 'configs/protocol-v3.json')['authority']['formal_training']
    assert sha(stable(runtime / 'records/data_preparation_complete.json')) == prior['cases'][CASE]['data_reuse_receipt_sha256']
    assert sha(stable(gru_runtime / 'records/data_preparation_complete.json')) == gru_prior['cases'][GRU]['data_reuse_receipt_sha256']
    configs = read(PRE / 'regenerated_configs' / (CASE + '.json'))
    old_bindings = cp.migration_bindings(runtime, CASE, OLD / 'candidates/base/runs')
    cp.bind_migration_configs(configs, old_bindings, OLD / 'candidates/base/runs')
    write(DEST / 'target_configs.json', configs)
    previous_members = {r['run_id']: r for r in prior['cases'][CASE]['members']}
    for rid in configs:
        state, source, checked, _, raw = cp.load_continuation(ORIGINAL / 'runs' / rid, 200)
        assert checked['config_sha256'] == previous_members[rid]['source_config_sha256']
        assert checked['completed_epochs'] >= previous_members[rid]['current_completed_epochs']
        if checked['completed_epochs'] == previous_members[rid]['current_completed_epochs']:
            assert sha(raw) == previous_members[rid]['source_checkpoint_sha256']
        del state, raw
        gc.collect()
    identity = next(iter(configs.values()))['effective_config']['device_identity']
    assert all(c['effective_config']['device_identity'] == identity for c in configs.values())
    write(DEST / 'hardware/lstm_expected.json', identity)
    write(DEST / 'hardware/gru_expected.json', gru_prior['cases'][GRU]['members'][0]['device_identity'])
    (DEST / 'gpu_probe.py').write_text(PROBE)
    detail = query([SLURM / 'scontrol', 'show', 'job', JOB])
    for expected in ('JobId=' + JOB, 'JobState=RUNNING',
                     'JobName=zj_legacy_lstm__historical_capacity_261006_pathfix',
                     'WorkDir=' + str(ORIGINAL),
                     'Command=' + str(ORIGINAL / 'hpc/pathfix_legacy_lstm__historical_capacity.slurm')):
        assert expected in detail['stdout'], 'target job identity differs: ' + expected
    before_queue = queue()
    writers = [line for line in before_queue['stdout'].splitlines() if CASE in line]
    assert len(writers) == 1 and writers[0].startswith(JOB + '|')
    write(DEST / 'source_job_before.json', {'detail': detail, 'queue': before_queue})
    # Slurm 19.05 uses --overcommit; newer Slurm can expose --overlap/--exact.
    help_text = query([SLURM / 'srun', '--help'])['stdout']
    step_flags = ['--overlap'] if '--overlap' in help_text else ['--overcommit']
    if '--exact' in help_text:
        step_flags.append('--exact')
    step = [SLURM / 'srun', '--jobid=' + JOB, '--nodes=1', '--ntasks=1', '--cpus-per-task=1',
            '--immediate=30', *step_flags, sys.executable, '-B', DEST / 'gpu_probe.py',
            '--case', CASE, '--runtime', runtime, '--expected', DEST / 'hardware/lstm_expected.json',
            '--output', DEST / 'hardware/lstm_gpu.json']
    measured = query(step, timeout=60, checked=False)
    write(DEST / 'lstm_gpu_step_receipt.json', measured)
    assert measured['returncode'] == 0, 'GPU identity step failed; old writer was not stopped'
    report['lstm_actual_gpu'] = read(DEST / 'hardware/lstm_gpu.json')
    assert report['lstm_actual_gpu']['matches']
    assert report['lstm_actual_gpu']['job_id'] == JOB
    # Only the human-authorized target writer is stopped. Complete checkpoints
    # are atomic; unfinished in-memory batches are intentionally not migrated.
    write(DEST / 'stop_attempt.json', {'job_id': JOB, 'at_utc': now(), 'reason': 'fixed200 case handoff'})
    stopped = query([SLURM / 'scancel', JOB], checked=False)
    write(DEST / 'stop_response.json', stopped)
    assert stopped['returncode'] == 0
    for _ in range(45):
        after_queue = queue()
        if not any(line.startswith(JOB + '|') for line in after_queue['stdout'].splitlines()):
            break
        time.sleep(2)
    assert not any(CASE in line for line in after_queue['stdout'].splitlines()), 'target writer still active'
    report['old_job_stopped'] = True
    report['scheduler_after_stop'] = after_queue
    report['old_job_accounting'] = query([SLURM / 'sacct', '-n', '-X', '-j', JOB,
                                        '--format=JobID,State,ExitCode,Start,End,NodeList', '-P'])
    spec = importlib.util.spec_from_file_location('migration_tool', OLD / 'release/tools/checkpoint_migration.py')
    tool = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(tool)
    for rid, target in configs.items():
        original = ORIGINAL / 'runs' / rid
        saved = DEST / 'sources' / CASE / rid
        saved.mkdir(parents=True)
        files = {}
        for name in ('config.json', 'continuation.pt', 'best.pt', 'epoch_100.pt', 'epoch_200.pt', 'first_optimizer_step.json'):
            path = original / name
            if path.is_file():
                raw = stable(path)
                (saved / name).write_bytes(raw)
                files[name] = {'source': str(path), 'sha256': sha(raw), 'bytes': len(raw)}
        assert not (original / 'failure.json').exists()
        state, source, checked, _, _ = cp.load_continuation(saved, 200)
        assert checked['config_sha256'] == previous_members[rid]['source_config_sha256']
        assert checked['completed_epochs'] >= previous_members[rid]['current_completed_epochs']
        archived = torch.load(ARCHIVE / CASE / rid / 'continuation.pt', map_location='cpu', weights_only=True)
        n0 = len(archived['values'])
        for key in ('values', 'train_metrics', 'shuffle_hashes'):
            assert state[key][:n0] == archived[key]
        steps = [float(v['step']) for v in state['optimizer']['state'].values()]
        assert min(steps) == max(steps) == sum(map(len, state['train_metrics']))
        family, capacity = CASE.split('__')
        effective = source['effective_config']
        parts = estimators.make_branches(models.make_parts(family, capacity, effective['seed']), effective['seed'] + 100000)[effective['method']]
        noise = filters.make_noise(parts.state_dim) if effective['method'].startswith('filter') else None
        estimators.configure_branch(parts, noise, effective['method'])
        optimizer = training.make_optimizer(parts, noise, effective['learning_rate'])
        candidate = runtime / 'runs' / rid
        receipt = tool.prepare_candidate(saved, target, candidate,
                                         expected_current=training.snapshot_parts(parts, noise), optimizer=optimizer)
        report['members'].append({'run_id': rid, 'completed_epochs': checked['completed_epochs'],
                                  'previous_preflight_epochs': previous_members[rid]['current_completed_epochs'],
                                  'source_files': files, 'source_checkpoint_sha256': files['continuation.pt']['sha256'],
                                  'archive672_history_prefix_preserved': True,
                                  'optimizer_step_min': min(steps), 'optimizer_step_max': max(steps),
                                  'candidate_dir': str(candidate),
                                  'candidate_receipt_sha256': sha(stable(candidate / 'migration_source.json')),
                                  'target_checkpoint_sha256': receipt['target_checkpoint_sha256']})
        assert sha(stable(original / 'continuation.pt')) == files['continuation.pt']['sha256']
        del state, archived, parts, noise, optimizer
        gc.collect()
    bindings = cp.migration_bindings(runtime, CASE, runtime / 'runs')
    cp.bind_migration_configs(configs, bindings, runtime / 'runs')
    write(DEST / 'lstm_migration_manifest.json', bindings)
    report['lstm_migration_manifest_digest'] = scheduler.digest_json(bindings)
    report['lstm_candidates_updated'] = 12
    # GRU's saved source has no writer; retain its authenticated 675 candidates.
    gru_bindings = cp.migration_bindings(gru_runtime, GRU, OLD / 'candidates/sqrt_gru_recovery/runs')
    assert scheduler.digest_json(gru_bindings) == gru_prior['cases'][GRU]['migration_manifest_digest']
    for member in gru_prior['cases'][GRU]['members']:
        folder = BASE / 'zhenjiang_complete_comparison_20261017_sqrt_recovery_001/runs' / member['run_id']
        assert sha(stable(folder / 'continuation.pt')) == member['source_checkpoint_sha256']
    report['gru_candidates_reused'] = 12
    report['gru_migration_manifest_digest'] = scheduler.digest_json(gru_bindings)
    slurm = '''#!/usr/bin/env bash
#SBATCH --job-name=zj003_A40_identity_261020
#SBATCH -p hgpu4
#SBATCH --nodelist=ngu102
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=1
#SBATCH --time=00:02:00
#SBATCH --output=DEST/logs/gru_gpu_%j.out
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
python -B DEST/gpu_probe.py --case explicit_gru__historical_capacity --runtime DEST/runtimes/sqrt_gru_recovery --expected DEST/hardware/gru_expected.json --output DEST/hardware/gru_gpu.json
'''.replace('DEST', str(DEST))
    script = DEST / 'gru_gpu_identity.slurm'
    script.write_text(slurm)
    report['gpu_node_snapshot'] = query([SLURM / 'scontrol', 'show', 'node', 'ngu102'])
    write(DEST / 'gru_gpu_submit_attempt.json', {'at_utc': now(), 'script_sha256': sha(script.read_bytes()), 'training_steps': 0})
    submitted = query([SLURM / 'xbatch', script], timeout=60, checked=False)
    write(DEST / 'gru_gpu_submit_response.json', submitted)
    match = re.fullmatch(r'Submitted batch job ([0-9]+)\s*', submitted['stdout'])
    assert submitted['returncode'] == 0 and match, 'submission response needs read-only reconciliation'
    report['gru_gpu_probe_job'] = match.group(1)
    report['gpu_probe_jobs_submitted'] = 1
    write(DEST / 'scheduler_jobs.json', {'gru_gpu_identity': match.group(1), 'old_lstm_stopped': JOB})
    for _ in range(15):
        if (DEST / 'hardware/gru_gpu.json').exists():
            break
        time.sleep(2)
    if (DEST / 'hardware/gru_gpu.json').exists():
        report['gru_actual_gpu'] = read(DEST / 'hardware/gru_gpu.json')
        assert report['gru_actual_gpu']['matches']
        assert report['gru_actual_gpu']['job_id'] == match.group(1)
        report['status'] = 'handoff_candidates_and_both_gpu_identities_complete'
    else:
        report['status'] = 'lstm_handoff_and_candidates_complete_gru_gpu_probe_submitted'
    report['gru_gpu_probe_accounting'] = query([SLURM / 'sacct', '-n', '-X', '-j', match.group(1),
        '--format=JobID,State,ExitCode,Start,End,NodeList', '-P'], checked=False)
except Exception as error:
    report['errors'].append({'type': type(error).__name__, 'message': str(error)})
    report['status'] = 'handoff_error_preserved'
report['finished_utc'] = now()
write(DEST / 'handoff_report.json', report)
print(json.dumps(report, sort_keys=True), flush=True)
print(json.dumps({'handoff_report_sha256': sha(stable(DEST / 'handoff_report.json')), 'root': str(DEST)}), flush=True)
if report['errors']:
    sys.exit(2)

HANDOFF_003
