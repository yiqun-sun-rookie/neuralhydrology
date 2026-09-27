#!/usr/bin/env bash
set -euo pipefail
export PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1
export OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1
export MKL_THREADING_LAYER=GNU MKL_SERVICE_FORCE_INTEL=1 CUDA_VISIBLE_DEVICES='' CUDA_CACHE_DISABLE=1
export PYTHONPATH=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r14_20260909/runtime_v2r14/pysite

printf '=== ACCEPTED INTEGRATED PACKAGE AND ONE FIRST-BASIN SUBMISSION ===\n'
/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python -B - \
  41c05dd241698887d4da2fb98fc1d81d5e08d9c83c7cfe935eccc7338fa32882 \
  e2b970621d3ac1e597791f103075e39003e9e00feb50845e90399c47241f2789 <<'PY'
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import zipfile

archive_sha, manifest_sha = sys.argv[1:]
archive_path = Path('/data1/home/sunyiq/hpc_mailbox/inbox/kalmannet-tukf09-noise-20260922/payload/full_budget_integrated_release_20260927_attempt1.zip')
remote_phase = Path('/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/full_budget_integrated_release_20260927_attempt1')
if remote_phase.exists() or remote_phase.is_symlink():
    raise SystemExit('exclusive integrated phase already exists; no submit')
with archive_path.open('rb') as stream:
    if hashlib.file_digest(stream, 'sha256').hexdigest() != archive_sha:
        raise SystemExit('integrated package fingerprint mismatch')
with zipfile.ZipFile(archive_path) as archive:
    names = archive.namelist()
    if len(names) != len(set(names)) or len(names) != 323 or names.count('bundle_manifest.json') != 1:
        raise SystemExit('integrated package membership ambiguous')
    manifest_raw = archive.read('bundle_manifest.json')
    if hashlib.sha256(manifest_raw).hexdigest() != manifest_sha:
        raise SystemExit('integrated manifest fingerprint mismatch')
    manifest = json.loads(manifest_raw)
    if manifest.get('path_mapping', {}).get('remote_root') != remote_phase.as_posix() + '/bundle':
        raise SystemExit('integrated remote root changed')
    deploy_name = 'hpc/tukf09_two_basin_full_budget_deploy_v2.py'
    authorization_name = 'hpc/tukf09_first_basin_integrated_release_authorization_v1.json'
    plugin_name = 'hpc/tukf09_test_temporary_paths_v1.py'
    supervisor_name = 'hpc/tukf09_two_basin_hpc_supervisor_v1.py'
    for name in (deploy_name, authorization_name, plugin_name, supervisor_name):
        if names.count(name) != 1 or name not in manifest.get('files', {}):
            raise SystemExit('integrated member missing: ' + name)
        data = archive.read(name)
        if manifest['files'][name] != {'sha256': hashlib.sha256(data).hexdigest(), 'size_bytes': len(data)}:
            raise SystemExit('integrated member record mismatch: ' + name)
    if hashlib.sha256(archive.read(supervisor_name)).hexdigest() != '4daed58001f95c474b633191454b1a664dce2596e676d4f701188c9c2b240e83':
        raise SystemExit('original output guard changed')
    authorization = json.loads(archive.read(authorization_name))
    if (authorization.get('failed_job_id') != '228129'
            or authorization.get('source_bundle_sha256') != 'be259aee2285fed7ab749762a78c11354a6aa8889fa153d3e36816e6dbc7e617'
            or authorization.get('authorized_basin_id') != '01047000'
            or authorization.get('maximum_new_submissions') != 1
            or authorization.get('second_basin_authorized') is not False
            or authorization.get('formal_evaluation_authorized') is not False
            or authorization.get('automatic_retry_or_requeue_authorized') is not False
            or authorization.get('remote_phase') != remote_phase.as_posix()):
        raise SystemExit('integrated authority changed')
    deploy_source = archive.read(deploy_name)

queue = subprocess.run(
    ['squeue', '-u', 'sunyiq', '-h', '-o', '%i|%j|%T'],
    check=True, text=True, capture_output=True, timeout=30,
).stdout
for line in queue.splitlines():
    fields = line.split('|')
    if len(fields) != 3:
        raise SystemExit('own queue format changed; no submit')
    if fields[1].startswith('tukf09-noise-'):
        raise SystemExit('another noise-stage job exists; no submit')

sys.argv = [deploy_name, '--first', archive_sha, manifest_sha]
exec(compile(deploy_source, deploy_name, 'exec'), {'__name__': '__main__', '__file__': deploy_name})
PY
