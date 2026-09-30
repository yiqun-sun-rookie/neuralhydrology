#!/usr/bin/env bash
set -euo pipefail
export PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1 PYTEST_DISABLE_PLUGIN_AUTOLOAD=1
export OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1
export MKL_THREADING_LAYER=GNU MKL_SERVICE_FORCE_INTEL=1 CUDA_VISIBLE_DEVICES='' CUDA_CACHE_DISABLE=1

phase='/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_local_selection_remaining_453_20260930_attempt1/canary11'
old='/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/full_budget_01142500_20260928_attempt1/bundle'
previous='/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/full_budget_01142500_20260929_attempt2/tukf09_full_budget_01142500_20260929.py'
private='/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r14_20260909/runtime_v2r14/pysite'
python='/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python'
export PYTHONPATH="$old/vendor:$private:$old:$old/hpc"
export CANARY11_PHASE="$phase" CANARY11_OLD="$old" CANARY11_PREVIOUS="$previous" CANARY11_PRIVATE="$private" CANARY11_PYTHON="$python"
CANARY11_BEGIN_TIME="$($python -B - <<'PY'
from datetime import datetime, timedelta
print((datetime.now().astimezone() + timedelta(minutes=5)).strftime('%Y-%m-%dT%H:%M:%S'))
PY
)"
export CANARY11_BEGIN_TIME

"$python" -B - <<'PY'
import hashlib
import json
import os
from pathlib import Path
import pwd
import re
import struct
import subprocess
import sys

import numpy as np
import torch

phase = Path(os.environ['CANARY11_PHASE'])
old = Path(os.environ['CANARY11_OLD'])
previous = Path(os.environ['CANARY11_PREVIOUS'])
private = Path(os.environ['CANARY11_PRIVATE'])
python = Path(os.environ['CANARY11_PYTHON'])
begin_time = os.environ['CANARY11_BEGIN_TIME']
expected_manifest_sha = 'c6cd14d7a72815e71dc4e3be9b679a04206029dbbd1f51beabd26fe47561f137'
expected_archive_sha = '2c7a78b80fe8e331cd37b43df010ddbbc776468f32d46baa99da051c2f5cf7f6'
execution_authorization_sha = 'f1f6488fa27cb225790be723f140c7621e29cae54aafa09f66ffbc2762d7a14d'
seq85_receipt_sha = '2958a5c50e646dd1e2d438b73767c45b6548d1215f3b7de9f562130d1c13abf6'
canaries = (
    ('01052500', 7), ('01031500', 8), ('01162500', 9), ('01022500', 10),
    ('02202600', 11), ('02297310', 12), ('01139000', 13), ('02296500', 15),
    ('02108000', 17), ('04040500', 18), ('01411300', 20),
)


def digest(path: Path) -> str:
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def plain_directory(path: Path) -> None:
    if path.is_symlink() or not path.is_dir():
        raise SystemExit('required plain directory changed: ' + str(path))


def plain_file(path: Path) -> None:
    if path.is_symlink() or not path.is_file():
        raise SystemExit('required plain file changed: ' + str(path))


def exact_children(path: Path, expected: set[str]) -> None:
    found = {entry.name for entry in path.iterdir()}
    if found != expected:
        raise SystemExit('exclusive staged contents changed: ' + str(path) + ' ' + repr(sorted(found)))


def semantic_array_identity(name: str, array: np.ndarray, dtype: str) -> dict:
    canonical = np.ascontiguousarray(array, dtype=np.dtype(dtype))
    name_bytes = name.encode('utf-8')
    dtype_bytes = dtype.encode('utf-8')
    value = hashlib.sha256()
    value.update(struct.pack('<Q', len(name_bytes)))
    value.update(name_bytes)
    value.update(struct.pack('<Q', len(dtype_bytes)))
    value.update(dtype_bytes)
    value.update(struct.pack('<q', canonical.ndim))
    for dimension in canonical.shape:
        value.update(struct.pack('<q', int(dimension)))
    value.update(canonical.tobytes(order='C'))
    return {'dtype': dtype, 'shape': [int(v) for v in canonical.shape], 'sha256': value.hexdigest()}


def write_exclusive(path: Path, value: dict) -> None:
    with path.open('x', encoding='utf-8') as stream:
        json.dump(value, stream, sort_keys=True, separators=(',', ':'), allow_nan=False)
        stream.write('\n')
        stream.flush()
        os.fsync(stream.fileno())


if pwd.getpwuid(os.getuid()).pw_name != 'sunyiq':
    raise SystemExit('wrong remote account')
for directory in (phase.parent, phase, phase / 'control', phase / 'logs', phase / 'cache', phase / 'tmp'):
    plain_directory(directory)
for path, expected in (
    (old / 'bundle_manifest.json', '4ebee2dcbd215e9751c86ca9895b84090956e7857d84b524fc87d60a3ea6afa1'),
    (old / 'hpc/tukf09_455_scaled_noise_common_v1.py', 'b4b70d97e4fdeca92ef1a7a8a6335a41d45acead5b40db5bdf1ab92ff70a3a5e'),
    (old / 'hpc/tukf09_455_scaled_noise_local_transfer_contract_v1.json', '27239212680bd370bd76f40e53337b7d68d80cbe4dc01feac2164bab4917f8a1'),
    (previous, '52a79db0169082449c8ea10548f957a7f1a38b4a9fdba84eefa96b5a188cf60a'),
):
    plain_file(path)
    if digest(path) != expected:
        raise SystemExit('sealed prerequisite changed: ' + str(path))

manifest_path = phase / 'payload_manifest.json'
plain_file(manifest_path)
if digest(manifest_path) != expected_manifest_sha:
    raise SystemExit('payload manifest fingerprint changed')
manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
expected_rows = [
    {'array_index': index, 'basin_id': basin, 'state_dimension': dimension}
    for index, (basin, dimension) in enumerate(canaries)
]
if (
    manifest.get('remote_phase') != phase.as_posix()
    or manifest.get('canaries') != expected_rows
    or manifest.get('maximum_scheduler_submissions') != 1
    or manifest.get('maximum_concurrent_tasks') != 4
    or manifest.get('wall_seconds_per_task') != 28800
    or manifest.get('evaluation_array_reads') != 0
    or manifest.get('formal_evaluation_authorized') is not False
    or manifest.get('transfer_library_authorized') is not False
    or manifest.get('automatic_retry_authorized') is not False
    or manifest.get('scientific_contract_changes_authorized') is not False
    or manifest.get('old_evidence_overwrite_authorized') is not False
):
    raise SystemExit('payload scope changed')
for name, expected in manifest['files'].items():
    path = phase / name
    plain_file(path)
    if digest(path) != expected['sha256'] or path.stat().st_size != expected['size_bytes']:
        raise SystemExit('payload member fingerprint changed: ' + name)

authorization = json.loads((phase / 'canary11_authorization.json').read_text(encoding='utf-8'))
if (
    authorization.get('authorized_basin_count') != 11
    or authorization.get('maximum_concurrent_tasks') != 4
    or authorization.get('maximum_scheduler_submissions') != 1
    or authorization.get('automatic_retry_or_requeue_authorized') is not False
    or authorization.get('formal_evaluation_authorized') is not False
    or authorization.get('transfer_library_authorized') is not False
):
    raise SystemExit('authorization boundary changed')
metadata = json.loads((phase / 'canary11_metadata.json').read_text(encoding='utf-8'))
if (
    metadata.get('canary_count') != 11
    or metadata.get('evaluation_array_reads') != 0
    or metadata.get('completed_excluded_basins') != ['01047000', '01142500']
    or set(metadata.get('basins', {})) != {basin for basin, _ in canaries}
):
    raise SystemExit('metadata boundary changed')
expected_array_names = {
    f'{basin}/{period}/{name}'
    for basin, _ in canaries
    for period in ('training', 'validation')
    for name in ('dates_ns', 'forcing', 'observations')
}
with np.load(phase / 'canary11_training_validation.npz', allow_pickle=False) as archive:
    if len(archive.files) != 66 or set(archive.files) != expected_array_names:
        raise SystemExit('training and validation array membership changed')
    for index, (basin, dimension) in enumerate(canaries):
        row = metadata['basins'][basin]
        if row.get('array_index') != index or row.get('dimension') != dimension or len(row.get('state_scale', [])) != dimension:
            raise SystemExit('canary identity or scale dimension changed: ' + basin)
        for period in ('training', 'validation'):
            for name in ('dates_ns', 'forcing', 'observations'):
                key = f'{basin}/{period}/{name}'
                dtype = '<i8' if name == 'dates_ns' else '<f8'
                if semantic_array_identity(key, archive[key], dtype) != row['semantic_members'][period][name]:
                    raise SystemExit('semantic array fingerprint changed: ' + key)

exact_children(phase / 'control', {'deployment.json'})
global_deployment = json.loads((phase / 'control/deployment.json').read_text(encoding='utf-8'))
if (
    global_deployment.get('status') != 'CANARY11_PAYLOAD_STAGED_NOT_SUBMITTED'
    or global_deployment.get('canary_count') != 11
    or global_deployment.get('maximum_concurrent_tasks') != 4
    or global_deployment.get('archive_sha256') != expected_archive_sha
    or global_deployment.get('manifest_sha256') != expected_manifest_sha
    or global_deployment.get('scheduler_submission_performed') is not False
    or global_deployment.get('model_execution_performed') is not False
    or global_deployment.get('formal_evaluation_authorized') is not False
    or global_deployment.get('transfer_library_authorized') is not False
):
    raise SystemExit('global deployment record changed')
for directory in (phase / 'logs', phase / 'cache', phase / 'tmp'):
    exact_children(directory, set())
for index, (basin, dimension) in enumerate(canaries):
    basin_root = phase / ('basin_' + basin)
    control = basin_root / 'control'
    plain_directory(basin_root)
    plain_directory(control)
    exact_children(basin_root, {'control'})
    exact_children(control, {'deployment.json'})
    deployment = json.loads((control / 'deployment.json').read_text(encoding='utf-8'))
    if (
        deployment.get('status') != 'CANARY11_BASIN_STAGED_NOT_SUBMITTED'
        or deployment.get('array_index') != index
        or deployment.get('basin_id') != basin
        or deployment.get('state_dimension') != dimension
        or deployment.get('archive_sha256') != expected_archive_sha
        or deployment.get('manifest_sha256') != expected_manifest_sha
        or deployment.get('scheduler_submission_performed') is not False
        or deployment.get('model_execution_performed') is not False
    ):
        raise SystemExit('basin deployment record changed: ' + basin)
if list(phase.glob('basin_*/run')):
    raise SystemExit('a canary run directory exists before submission')

if Path(sys.executable).resolve() != python.resolve() or sys.version_info[:3] != (3, 11, 13):
    raise SystemExit('Python runtime changed')
if np.__version__ != '1.26.4' or not Path(np.__file__).resolve().is_relative_to(private.resolve()):
    raise SystemExit('NumPy runtime changed')
if torch.__version__ != '2.2.2+cu121' or not Path(torch.__file__).resolve().is_relative_to(private.resolve()):
    raise SystemExit('PyTorch runtime changed')
torch.set_num_threads(1)
torch.set_num_interop_threads(1)
if torch.get_num_threads() != 1 or torch.get_num_interop_threads() != 1:
    raise SystemExit('single-thread numerical execution unavailable')

slurm_path = phase / 'canary11_full_budget.slurm'
slurm_text = slurm_path.read_text(encoding='utf-8')
for marker in (
    '#SBATCH --partition=hcpu48y', '#SBATCH --cpus-per-task=1', '#SBATCH --time=08:00:00',
    '#SBATCH --array=0-10%4', '#SBATCH --nice=10000', '#SBATCH --no-requeue',
    "OMP_NUM_THREADS=1", "MKL_NUM_THREADS=1", "OPENBLAS_NUM_THREADS=1", "NUMEXPR_NUM_THREADS=1",
    "CUDA_VISIBLE_DEVICES=''",
):
    if slurm_text.count(marker) != 1:
        raise SystemExit('job resource or isolation marker changed: ' + marker)
partition = subprocess.run(
    ['scontrol', 'show', 'partition', 'hcpu48y', '-o'], check=True, text=True,
    capture_output=True, timeout=30,
).stdout.strip()
if ' State=UP ' not in (' ' + partition + ' ') or ' OverSubscribe=NO ' not in (' ' + partition + ' '):
    raise SystemExit('processor partition unavailable or allocation mode changed')
configuration = subprocess.run(
    ['scontrol', 'show', 'config'], check=True, text=True, capture_output=True, timeout=30,
).stdout
match = re.search(r'(?m)^\s*MaxArraySize\s*=\s*(\d+)\s*$', configuration)
if match is None or int(match.group(1)) < 11:
    raise SystemExit('scheduler array capacity unavailable or ambiguous')
queue = subprocess.run(
    ['squeue', '-u', 'sunyiq', '-h', '-o', '%i|%j|%T|%R|%M'], check=True,
    text=True, capture_output=True, timeout=30,
).stdout

write_exclusive(phase / 'control/submission_attempt.json', {
    'status': 'CANARY11_ARRAY_SUBMISSION_CONSUMED_OUTCOME_UNKNOWN_UNTIL_RECEIPT',
    'authorized_basin_count': 11,
    'array_indices': '0-10',
    'maximum_concurrent_tasks': 4,
    'maximum_scheduler_submissions': 1,
    'partition': 'hcpu48y',
    'cpus_per_task': 1,
    'wall_seconds_per_task': 28800,
    'scheduled_earliest_start_local': begin_time,
    'execution_authorization_sha256': execution_authorization_sha,
    'seq85_receipt_sha256': seq85_receipt_sha,
    'payload_manifest_sha256': expected_manifest_sha,
    'slurm_script_sha256': digest(slurm_path),
    'automatic_retry_or_requeue_authorized': False,
    'formal_evaluation_authorized': False,
    'transfer_library_authorized': False,
    'scientific_contract_changes_authorized': False,
    'old_evidence_overwrite_authorized': False,
    'queue_before_submission': queue,
    'scheduler_submission_count_before_record': 0,
    'model_execution_count_before_record': 0,
    'evaluation_array_reads': 0,
})
print('CANARY11_FINAL_PREFLIGHT_PASSED_SUBMISSION_ATTEMPT_CONSUMED ' + json.dumps({
    'canary_count': 11,
    'maximum_concurrent_tasks': 4,
    'scheduled_earliest_start_local': begin_time,
    'partition': partition,
    'max_array_size': int(match.group(1)),
    'scheduler_submission_performed_at_marker': False,
    'model_execution_performed_at_marker': False,
    'evaluation_array_reads': 0,
}, sort_keys=True), flush=True)
PY

submission_output="$(sbatch --parsable --begin="$CANARY11_BEGIN_TIME" "$phase/canary11_full_budget.slurm")"
submission_output="${submission_output//$'\r'/}"
if [[ ! "$submission_output" =~ ^[0-9]+(\;[A-Za-z0-9._-]+)?$ ]]; then
  printf 'AMBIGUOUS_SBATCH_OUTPUT=%q\n' "$submission_output" >&2
  exit 86
fi
CANARY11_JOB_ID="${submission_output%%;*}"
export CANARY11_JOB_ID CANARY11_SUBMISSION_OUTPUT="$submission_output"

"$python" -B - <<'PY'
import hashlib
import json
import os
from pathlib import Path
import subprocess

phase = Path(os.environ['CANARY11_PHASE'])
job_id = os.environ['CANARY11_JOB_ID']
raw = os.environ['CANARY11_SUBMISSION_OUTPUT']
begin_time = os.environ['CANARY11_BEGIN_TIME']


def digest(path: Path) -> str:
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def write_exclusive(path: Path, value: dict) -> None:
    with path.open('x', encoding='utf-8') as stream:
        json.dump(value, stream, sort_keys=True, separators=(',', ':'), allow_nan=False)
        stream.write('\n')
        stream.flush()
        os.fsync(stream.fileno())


if not job_id.isdigit() or raw.split(';', 1)[0] != job_id:
    raise SystemExit('confirmed scheduler identifier is malformed')
attempt_path = phase / 'control/submission_attempt.json'
attempt = json.loads(attempt_path.read_text(encoding='utf-8'))
if (
    attempt.get('status') != 'CANARY11_ARRAY_SUBMISSION_CONSUMED_OUTCOME_UNKNOWN_UNTIL_RECEIPT'
    or attempt.get('maximum_scheduler_submissions') != 1
    or attempt.get('scheduled_earliest_start_local') != begin_time
):
    raise SystemExit('submission attempt record changed after scheduler call')
submission_path = phase / 'control/submission.json'
write_exclusive(submission_path, {
    'status': 'CANARY11_ARRAY_SUBMISSION_CONFIRMED_NOT_MODEL_COMPLETION',
    'job_id': job_id,
    'raw_sbatch_output': raw,
    'array_indices': '0-10',
    'maximum_concurrent_tasks': 4,
    'scheduled_earliest_start_local': begin_time,
    'slurm_script_sha256': digest(phase / 'canary11_full_budget.slurm'),
    'submission_attempt_sha256': digest(attempt_path),
    'scheduler_submission_count': 1,
    'automatic_retry_or_requeue_authorized': False,
    'formal_evaluation_authorized': False,
    'transfer_library_authorized': False,
    'model_completion_claim': False,
    'scientific_performance_claim': False,
    'evaluation_array_reads': 0,
})
scontrol = subprocess.run(
    ['scontrol', 'show', 'job', job_id, '-o'], text=True, capture_output=True, timeout=30,
)
squeue = subprocess.run(
    ['squeue', '-j', job_id, '-h', '-o', '%i|%j|%T|%R|%M'],
    text=True, capture_output=True, timeout=30,
)
snapshot = {
    'status': 'CANARY11_INITIAL_SCHEDULER_SNAPSHOT_AFTER_ONE_CONFIRMED_SUBMISSION',
    'job_id': job_id,
    'scontrol_exit_code': scontrol.returncode,
    'scontrol_stdout': scontrol.stdout,
    'scontrol_stderr': scontrol.stderr,
    'squeue_exit_code': squeue.returncode,
    'squeue_stdout': squeue.stdout,
    'squeue_stderr': squeue.stderr,
    'scheduler_submission_count': 1,
    'model_completion_claim': False,
    'evaluation_array_reads': 0,
}
write_exclusive(phase / 'control/initial_scheduler_snapshot.json', snapshot)
print('CANARY11_ARRAY_SUBMISSION_CONFIRMED_NOT_MODEL_COMPLETION ' + json.dumps({
    'job_id': job_id,
    'array_indices': '0-10',
    'maximum_concurrent_tasks': 4,
    'scheduled_earliest_start_local': begin_time,
    'scontrol_exit_code': scontrol.returncode,
    'squeue_exit_code': squeue.returncode,
    'squeue': squeue.stdout,
    'scheduler_submission_count': 1,
    'model_completion_claim': False,
    'evaluation_array_reads': 0,
    'formal_evaluation_performed': False,
}, sort_keys=True), flush=True)
PY
