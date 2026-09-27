#!/usr/bin/env bash
set -euo pipefail
export PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1
export OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1
export MKL_THREADING_LAYER=GNU MKL_SERVICE_FORCE_INTEL=1 CUDA_VISIBLE_DEVICES=''
export PYTHONPATH=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r14_20260909/runtime_v2r14/pysite

printf '%s\n' '=== FIRST-BASIN TERMINAL READ-ONLY TECHNICAL ACCEPTANCE ==='
date -u '+UTC=%Y-%m-%dT%H:%M:%SZ'
/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python -B - <<'PY'
import hashlib
import json
from pathlib import Path
import stat
import subprocess
import sys

phase = Path('/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/full_budget_integrated_release_20260927_attempt1')
archive = Path('/data1/home/sunyiq/hpc_mailbox/inbox/kalmannet-tukf09-noise-20260922/payload/full_budget_integrated_release_20260927_attempt1.zip')
basin = phase / 'basin_01047000'
model = basin / 'run/model'
job_id = '228327'
archive_sha = '41c05dd241698887d4da2fb98fc1d81d5e08d9c83c7cfe935eccc7338fa32882'
manifest_sha = 'e2b970621d3ac1e597791f103075e39003e9e00feb50845e90399c47241f2789'

def read_json(path):
    if not path.is_file() or path.is_symlink():
        raise RuntimeError('required regular unlinked JSON missing: ' + str(path))
    return json.loads(path.read_text(encoding='utf-8'))

if not phase.is_dir() or phase.is_symlink() or not basin.is_dir() or basin.is_symlink():
    raise RuntimeError('exclusive first-basin phase missing or linked')
for relative in ('control/submission_attempt.json', 'control/submission.json', 'control/job_gate.json',
                 'run/model/started.json', 'run/model/summary.json', 'run/model/history.npz',
                 'run/model/manifest.final.sha256.json', 'run/supervisor.json', 'run/stdout.log', 'run/stderr.log'):
    path = basin / relative
    if not path.is_file() or path.is_symlink():
        raise RuntimeError('required completed-run file missing or linked: ' + relative)
if not archive.is_file() or archive.is_symlink():
    raise RuntimeError('original uploaded archive missing or linked')
with archive.open('rb') as stream:
    if hashlib.file_digest(stream, 'sha256').hexdigest() != archive_sha:
        raise RuntimeError('original uploaded archive fingerprint changed')

accounting = subprocess.run(
    ['sacct', '-X', '-j', job_id, '-P', '-n',
     '--format=JobID,JobName,Partition,AllocCPUS,ReqCPUS,AllocTRES,ReqTRES,ElapsedRaw,State,ExitCode'],
    check=True, text=True, capture_output=True, timeout=30,
).stdout
rows = [line for line in accounting.splitlines() if line.strip()]
print('ACCOUNTING ' + json.dumps(rows, separators=(',', ':')))
if len(rows) != 1:
    raise RuntimeError('job accounting is not unique')
fields = rows[0].split('|')
if len(fields) != 10 or fields[0] != job_id or fields[1] != 'tukf09-noise-int-v2r9-0927' or fields[2] != 'hcpu48y' or fields[3:5] != ['1', '1'] or not fields[7].isdigit() or fields[8:] != ['COMPLETED', '0:0']:
    raise RuntimeError('job terminal state, resource allocation, or exit code changed')

sys.path.insert(0, str(phase / 'bundle/hpc'))
from tukf09_two_basin_full_budget_deploy_v2 import _digest, _read_json, _require_exact_one_core_tres, _validate_first_control_chain
from tukf09_two_basin_full_budget_gate_v2 import PRIVATE_PYTHON_PATH, REMOTE_ROOT, verify_bundle
from verify_tukf09_two_basin_full_budget_v2 import verify_result_directory
import numpy as np

_require_exact_one_core_tres(fields[5], fields[6])
expected_gate = verify_bundle(REMOTE_ROOT, manifest_sha)
deployed = _read_json(phase / 'control/deployed.json')
attempt_path = basin / 'control/submission_attempt.json'
validated_job = _validate_first_control_chain(
    deployed=deployed,
    attempt=_read_json(attempt_path),
    submission=_read_json(basin / 'control/submission.json'),
    job_gate=_read_json(basin / 'control/job_gate.json'),
    supervisor=_read_json(basin / 'run/supervisor.json'),
    started=_read_json(model / 'started.json'),
    archive_sha=archive_sha,
    manifest_sha=manifest_sha,
    attempt_sha=_digest(attempt_path),
    expected_gate=expected_gate,
)
if validated_job != job_id:
    raise RuntimeError('control-chain job ID differs from scheduler accounting')
with (basin / 'run/stdout.log').open('rb') as stream:
    needle = b'FULL_BUDGET_MODEL_STARTED basin=01047000 dimension=7'
    marker = False
    overlap = b''
    while True:
        chunk = stream.read(65536)
        if not chunk:
            break
        marker = needle in overlap + chunk
        if marker:
            break
        overlap = chunk[-len(needle):]
    if not marker:
        raise RuntimeError('real model calculation-entry marker missing')
metadata = read_json(phase / 'bundle/input/metadata.json')
row = metadata['basins']['01047000']
audit = verify_result_directory(
    model,
    basin_id='01047000',
    dimension=7,
    expected_scale=np.asarray(row['state_scale'], dtype=np.float64),
    expected_fixed_r_b=float(row['fixed_r_b']),
    expected_source_gate=expected_gate,
    expected_bundle_manifest_sha256=manifest_sha,
    expected_python_executable='/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python',
    expected_private_python_path=PRIVATE_PYTHON_PATH,
)
if audit['status'] != 'PASS_NOT_FORMAL_EVALUATION' or audit['evaluation_array_reads'] != 0:
    raise RuntimeError('independent array verification did not pass')

output_bytes = 0
for root in (basin, phase / 'logs'):
    if not root.is_dir() or root.is_symlink():
        raise RuntimeError('output root missing or linked: ' + str(root))
    for path in root.rglob('*'):
        mode = path.lstat().st_mode
        if stat.S_ISLNK(mode):
            raise RuntimeError('linked output forbidden: ' + str(path))
        if stat.S_ISREG(mode):
            if root == basin or path.name in (f'job-{job_id}.out', f'job-{job_id}.err'):
                output_bytes += path.stat().st_size
if output_bytes > 100 * 2**20:
    raise RuntimeError('first-basin output exceeds frozen 100 MiB limit')
print('CONTROL_CHAIN_PASS job_id=' + job_id)
print('RESULT_MANIFEST_SHA256=' + audit['manifest_sha256'])
print('INDEPENDENT_ARRAY_AUDIT ' + json.dumps({
    'status': audit['status'],
    'basin_id': audit['basin_id'],
    'dimension': audit['dimension'],
    'maximum_q_exp_ulp_distance': audit['maximum_q_exp_ulp_distance'],
    'evaluation_array_reads': audit['evaluation_array_reads'],
}, sort_keys=True, separators=(',', ':')))
print('OUTPUT_BYTES=' + str(output_bytes))
print('READ_ONLY_FIRST_BASIN_TECHNICAL_ACCEPTANCE_PASS')
PY
