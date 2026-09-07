#!/usr/bin/env bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1 PYTHONOPTIMIZE=0
printf '%s\n' 'channel=kalmannet-daily-perbasin sequence=61 purpose=readonly-first-basin-terminal-evidence-and-shared-resource-state'
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B -u - <<'PY_EVIDENCE'
import datetime, hashlib, json, pathlib, subprocess

root = pathlib.Path('/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901')
execution_id = 'DAILY_CAMELS_KNET_PER_BASIN_PILOT_04105700_V2_20260902_A43_HISTORYFIX1_A800_TRAIN1_SEQ57'
run_directory = root / 'runs' / execution_id
launch = root / 'node_recovery_20260907/train_04105700_historyfix1_seq57'
status = root / 'status'
job_id = '223629'

def require(condition, message):
    if not condition:
        raise RuntimeError(message)

def emit(value):
    print(json.dumps(value, sort_keys=True, allow_nan=False), flush=True)

def raw_json_record(path, limit=2000000):
    require(path.is_file() and not path.is_symlink() and path.resolve() == path, 'unexpected JSON path: ' + str(path))
    data = path.read_bytes()
    require(len(data) <= limit, 'JSON exceeds bound: ' + str(path))
    text = data.decode('utf-8')
    json.loads(text)
    emit({'section': 'RAW_JSON_TEXT', 'path': str(path), 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest(), 'text': text})

require(root.is_dir() and root.resolve() == root, 'root differs')
emit({'section': 'IDENTITY', 'observed_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'request_sequence': 61, 'execution_id': execution_id, 'job_id': job_id, 'run_directory': str(run_directory)})

for path in [
    launch / 'pre_submit_baseline.json',
    launch / 'submission_receipt.json',
    run_directory / 'preflight.json',
    run_directory / 'epoch_history.json',
    run_directory / 'result_summary.json',
    run_directory / 'completion.marker.json',
    run_directory / 'manifest.sha256.json',
    status / (execution_id + '.audit.json'),
]:
    raw_json_record(path)

stdout_path = status / (execution_id + '.slurm-' + job_id + '.stdout')
stderr_path = status / (execution_id + '.slurm-' + job_id + '.stderr')
for label, path in [('STDOUT', stdout_path), ('STDERR', stderr_path)]:
    require(path.is_file() and not path.is_symlink() and path.resolve() == path, 'unexpected log path: ' + str(path))
    data = path.read_bytes()
    text = data.decode('utf-8', errors='replace')
    emit({'section': label, 'path': str(path), 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest(), 'first_lines': text.splitlines()[:16], 'last_lines': text.splitlines()[-16:]})
require(stderr_path.stat().st_size == 0, 'training stderr is not empty')

for label, args in [
    ('ACCOUNTING', ['sacct', '-n', '-P', '-j', job_id, '--format=JobID,JobName%100,State,ExitCode,Elapsed,NodeList,AllocCPUS,AllocTRES%100']),
    ('PARTITION', ['scontrol', 'show', 'partition', 'hgpu8']),
    ('NODE_NGU201', ['scontrol', 'show', 'node', 'ngu201']),
    ('NODE_NGU202', ['scontrol', 'show', 'node', 'ngu202']),
    ('NODE_NGU203', ['scontrol', 'show', 'node', 'ngu203']),
    ('SINFO', ['sinfo', '-N', '-p', 'hgpu8', '-h', '-o', '%N|%T|%c|%C|%G']),
]:
    result = subprocess.run(args, capture_output=True, text=True, timeout=30)
    emit({'section': label, 'args': args, 'exit_code': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr})
    require(result.returncode == 0, 'read-only scheduler command failed: ' + label)

emit({'status': 'READONLY_TERMINAL_EVIDENCE_AND_RESOURCE_STATE_OBSERVED', 'request_sequence': 61, 'job_id': job_id, 'compute_submissions': 0, 'task_file_writes': 0, 'checkpoint_content_reads': 0, 'prediction_array_reads': 0, 'formal_evaluation_access_count': 0})
PY_EVIDENCE
