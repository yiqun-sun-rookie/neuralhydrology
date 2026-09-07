#!/usr/bin/env bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1 PYTHONOPTIMIZE=0
printf '%s\n' 'channel=kalmannet-daily-perbasin sequence=68 purpose=readonly-third-basin-training-terminal'
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B -u - <<'PY_PROGRESS'
import datetime, hashlib, json, pathlib, re, subprocess

root = pathlib.Path('/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901')
execution_id = 'DAILY_CAMELS_KNET_PER_BASIN_PILOT_09035800_V2_20260902_A45_HISTORYFIX1_A800_TRAIN1_SEQ66'
launch = root / 'node_recovery_20260907/train_09035800_historyfix1_seq66'
run_directory = root / 'runs' / execution_id
status = root / 'status'

def require(condition, message):
    if not condition:
        raise RuntimeError(message)

def emit(value):
    print(json.dumps(value, sort_keys=True, allow_nan=False), flush=True)

def read_text_file(path, limit=2000000):
    require(path.is_file() and not path.is_symlink() and path.resolve() == path, 'unexpected file: ' + str(path))
    require(path.stat().st_size <= limit, 'text exceeds bound: ' + str(path))
    data = path.read_bytes()
    return data, data.decode('utf-8')

require(root.is_dir() and root.resolve() == root, 'root differs')
receipt_bytes, receipt_text = read_text_file(launch / 'submission_receipt.json', 100000)
receipt = json.loads(receipt_text)
require(receipt['request_sequence'] == 66 and receipt['execution_id'] == execution_id, 'submission identity differs')
require(receipt['submission_exit_code'] == 0 and len(receipt['job_matches']) == 1, 'submission is not unambiguous')
job_id = receipt['job_matches'][0]
require(isinstance(job_id, str) and re.fullmatch(r'[0-9]+', job_id), 'invalid job identifier')
emit({'observed_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'request_sequence': 68, 'job_id': job_id, 'execution_id': execution_id, 'submission_receipt_sha256': hashlib.sha256(receipt_bytes).hexdigest(), 'run_directory': str(run_directory)})

for label, args in [
    ('QUEUE', ['squeue', '-h', '-j', job_id, '-o', '%i|%j|%T|%M|%R']),
    ('ACCOUNTING', ['sacct', '-n', '-P', '-j', job_id, '--format=JobID,JobName%100,State,ExitCode,Elapsed,NodeList,AllocCPUS,AllocTRES%100']),
    ('CONTROLLER', ['scontrol', 'show', 'job', job_id]),
]:
    result = subprocess.run(args, capture_output=True, text=True, timeout=30)
    emit({'section': label, 'exit_code': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr})
    job_purged = label in {'QUEUE', 'CONTROLLER'} and 'Invalid job id specified' in (result.stdout + result.stderr)
    require(result.returncode == 0 or job_purged, 'scheduler read failed: ' + label)

history_path = run_directory / 'epoch_history.json'
if history_path.exists():
    history_bytes, history_text = read_text_file(history_path)
    history = json.loads(history_text)
    require(isinstance(history, list), 'history is not a list')
    selected = ['epoch', 'epoch_status', 'validation_status', 'optimizer_steps', 'training_forecast_error_events', 'training_objective', 'same_segment_post_step_objective', 'checkpoint_objective_728', 'gradient_norm_before_clip', 'parameter_sha256', 'checkpoint_ratio', 'post_step_ratio']
    emit({'section': 'TRAINING_HISTORY', 'rows': len(history), 'sha256': hashlib.sha256(history_bytes).hexdigest(), 'last_rows': [{key: row.get(key) for key in selected} for row in history[-2:]], 'training_update_recorded': any(type(row.get('optimizer_steps')) is int and row['optimizer_steps'] > 0 for row in history)})
else:
    emit({'section': 'TRAINING_HISTORY', 'exists': False, 'training_update_recorded': False})

for label, directory, pattern in [('CHECKPOINT_METADATA_ONLY', run_directory / 'checkpoints', 'epoch_*.pt'), ('ATTEMPT_METADATA', run_directory / 'attempts', 'epoch_*.started.json')]:
    entries = []
    if directory.exists():
        require(directory.is_dir() and not directory.is_symlink() and directory.resolve() == directory, 'unexpected directory')
        for path in sorted(directory.glob(pattern)):
            require(path.is_file() and not path.is_symlink(), 'unexpected member')
            info = path.stat()
            entries.append({'name': path.name, 'bytes': info.st_size, 'mtime_ns': info.st_mtime_ns})
    emit({'section': label, 'count': len(entries), 'last_members': entries[-3:]})

for path in [run_directory / 'completion.marker.json', run_directory / 'result_summary.json', run_directory / 'unregistered_numeric_failure_event.json', status / (execution_id + '.audit.json')]:
    if path.exists():
        data, text = read_text_file(path)
        parsed = json.loads(text)
        keys = ['terminal_state', 'technical_success', 'completed_epoch', 'optimizer_steps', 'scientific_capability_status', 'formal_evaluation_access_count', 'failure_state', 'failure_stage', 'exception_type', 'exception_message', 'verification_passed']
        emit({'section': 'TERMINAL_OR_FAILURE', 'path': str(path), 'sha256': hashlib.sha256(data).hexdigest(), 'fields': {key: parsed[key] for key in keys if key in parsed}})

for path in [status / (execution_id + '.slurm-' + job_id + '.stdout'), status / (execution_id + '.slurm-' + job_id + '.stderr'), status / (execution_id + '.gpu.csv')]:
    if not path.exists():
        emit({'section': 'LOG_TAIL', 'path': str(path), 'exists': False})
        continue
    require(path.is_file() and not path.is_symlink() and path.resolve() == path, 'log path differs')
    info = path.stat()
    with path.open('rb') as stream:
        stream.seek(max(0, info.st_size - 10000))
        tail = stream.read(10000).decode('utf-8', errors='replace')
    emit({'section': 'LOG_TAIL', 'path': str(path), 'bytes': info.st_size, 'mtime_ns': info.st_mtime_ns, 'last_lines': tail.splitlines()[-8:]})

emit({'status': 'READONLY_TRAINING_TERMINAL_OBSERVED', 'request_sequence': 68, 'job_id': job_id, 'compute_submissions': 0, 'task_file_writes': 0, 'checkpoint_content_reads': 0, 'formal_evaluation_access_count': 0})
PY_PROGRESS
