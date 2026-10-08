#!/usr/bin/env bash
# Read only: verify preserved histories and actual optimizer advancement after recovery.
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
python -B - <<'PY'
import datetime, hashlib, io, json, math, os, pathlib, subprocess
import torch

root = pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261008_recovery_002')
prepared = json.loads((root / 'records/recovery_preparation_complete.json').read_text())
parent = pathlib.Path(prepared['parent_root'])
case = prepared['case']
newjob = str(json.loads((root / 'records/scheduler_jobs.json').read_text())[case])
oldjob = str(prepared['source_job'])
assert prepared['source_checkpoints_preserved'] and prepared['scientific_protocol_unchanged']
assert hashlib.sha256((root / 'configs/protocol-v3.json').read_bytes()).hexdigest() == hashlib.sha256((parent / 'configs/protocol-v3.json').read_bytes()).hexdigest()
torch.set_num_threads(1)

def load_checkpoint(path):
    with path.open('rb') as stream:
        stat = os.fstat(stream.fileno())
        raw = stream.read()
    state = torch.load(io.BytesIO(raw), map_location='cpu', weights_only=True)
    return state, {'sha256': hashlib.sha256(raw).hexdigest(), 'bytes': len(raw),
                   'mtime_beijing': datetime.datetime.fromtimestamp(stat.st_mtime, datetime.timezone(datetime.timedelta(hours=8))).isoformat()}

def tensors(value):
    if isinstance(value, torch.Tensor):
        yield value
    elif isinstance(value, dict):
        for item in value.values():
            yield from tensors(item)
    elif isinstance(value, (list, tuple)):
        for item in value:
            yield from tensors(item)

rows = []
for migration in prepared['migrations']:
    run = migration['run']
    assert migration['only_checkpoint_metadata_change'] == 'config_sha256'
    old, oldstat = load_checkpoint(pathlib.Path(migration['source_checkpoint']))
    new, newstat = load_checkpoint(root / 'runs' / run / 'continuation.pt')
    original_config = parent / 'runs' / run / 'config.json'
    current_config = root / 'runs' / run / 'config.json'
    assert oldstat['sha256'] == migration['source_checkpoint_sha256']
    assert hashlib.sha256(original_config.read_bytes()).hexdigest() == migration['source_config_sha256'] == old['config_sha256']
    assert hashlib.sha256(current_config.read_bytes()).hexdigest() == migration['recovery_config_sha256'] == new['config_sha256']
    prefix = len(old['values'])
    epochs = len(new['values'])
    assert prefix == migration['epochs_preserved'] and epochs > prefix
    assert epochs == len(new['train_metrics']) == len(new['shuffle_hashes'])
    assert all(math.isfinite(v) and v >= 0 for v in new['values'])
    assert new['values'][:prefix] == old['values']
    assert new['train_metrics'][:prefix] == old['train_metrics']
    assert new['shuffle_hashes'][:prefix] == old['shuffle_hashes']
    assert all(bool(torch.isfinite(t).all()) for t in tensors(new))
    old_steps = {str(k): float(v['step']) for k, v in old['optimizer']['state'].items()}
    new_steps = {str(k): float(v['step']) for k, v in new['optimizer']['state'].items()}
    assert set(old_steps) == set(new_steps) and old_steps
    assert all(new_steps[k] > old_steps[k] for k in old_steps)
    before = list(tensors(old['current']))
    after = list(tensors(new['current']))
    assert len(before) == len(after) and before
    assert any(not torch.equal(a, b) for a, b in zip(before, after))
    rows.append({'run': run, 'source_epochs': prefix, 'current_saved_epochs': epochs,
                 'all_source_validation_values_preserved': True, 'all_source_batch_history_preserved': True,
                 'all_source_shuffle_history_preserved': True, 'source_checkpoint_unchanged': True,
                 'configuration_binding_verified': True, 'all_saved_tensors_finite': True,
                 'model_parameters_changed_since_source_checkpoint': True,
                 'optimizer_parameters_checked': len(old_steps),
                 'minimum_added_optimizer_steps': min(new_steps[k] - old_steps[k] for k in old_steps),
                 'checkpoint': newstat})
queries = []
for command in (['squeue', '-h', '-j', newjob + ',' + oldjob, '-o', '%i|%T|%N'],
                ['sacct', '-n', '-X', '-j', newjob + ',' + oldjob, '--format=JobID,State,ExitCode,NodeList', '-P']):
    r = subprocess.run(command, capture_output=True, text=True, timeout=30)
    assert r.returncode == 0
    queries.append({'command': command, 'stdout': r.stdout, 'stderr': r.stderr})
assert not any(line.startswith(oldjob + '|') for line in queries[0]['stdout'].splitlines())
assert any(line.startswith(newjob + '|RUNNING|') for line in queries[0]['stdout'].splitlines())
print(json.dumps({'status': 'read_only_authenticated_resume_audit_passed',
                  'checked_at_beijing': datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
                  'case': case, 'source_job': oldjob, 'active_job': newjob,
                  'protocol_bytes_unchanged': True, 'members': rows, 'scheduler_queries': queries,
                  'evaluation_values_read': False, 'data_inputs_read': False,
                  'checkpoints_loaded_on_cpu_only': True, 'training_or_checkpoint_files_written': False}, ensure_ascii=True))
PY
