#!/usr/bin/env bash
set -euo pipefail
export PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1
export OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1
export MKL_THREADING_LAYER=GNU MKL_SERVICE_FORCE_INTEL=1 CUDA_VISIBLE_DEVICES='' CUDA_CACHE_DISABLE=1
export PYTHONPATH=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r14_20260909/runtime_v2r14/pysite

echo '=== FIRST-BASIN OUTPUT-GUARD RELEASE AND ONE SUBMISSION ==='
/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python -B - \
  be259aee2285fed7ab749762a78c11354a6aa8889fa153d3e36816e6dbc7e617 \
  8b88fdb0238d97c006fc7b07381f4b0e5c49d0fb9b7df5b1e0acfec8bab132af <<'PY'
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import zipfile

archive_sha, manifest_sha = sys.argv[1:]
archive_path = Path('/data1/home/sunyiq/hpc_mailbox/inbox/kalmannet-tukf09-noise-20260922/payload/full_budget_recovery_v2r8_20260927.zip')
remote_phase = Path('/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/full_budget_recovery_v2r8_20260927')
if remote_phase.exists() or remote_phase.is_symlink():
    raise SystemExit('exclusive recovery directory already exists; no submit')
with archive_path.open('rb') as stream:
    if hashlib.file_digest(stream, 'sha256').hexdigest() != archive_sha:
        raise SystemExit('recovery payload fingerprint mismatch')
with zipfile.ZipFile(archive_path) as archive:
    names = archive.namelist()
    if len(names) != len(set(names)) or names.count('bundle_manifest.json') != 1:
        raise SystemExit('recovery payload membership is duplicated or incomplete')
    manifest_raw = archive.read('bundle_manifest.json')
    if hashlib.sha256(manifest_raw).hexdigest() != manifest_sha:
        raise SystemExit('recovery manifest fingerprint mismatch')
    manifest = json.loads(manifest_raw)
    if manifest.get('path_mapping', {}).get('remote_root') != remote_phase.as_posix() + '/bundle':
        raise SystemExit('recovery remote root changed')
    deploy_name = 'hpc/tukf09_two_basin_full_budget_deploy_v2.py'
    authorization_name = 'hpc/tukf09_first_basin_recovery_authorization_v2r8_20260927.json'
    supervisor_name = 'hpc/tukf09_two_basin_hpc_supervisor_v1.py'
    for name in (deploy_name, authorization_name, supervisor_name):
        if names.count(name) != 1 or name not in manifest.get('files', {}):
            raise SystemExit('required recovery member is missing or ambiguous: ' + name)
        source = archive.read(name)
        record = manifest['files'][name]
        if record != {'sha256': hashlib.sha256(source).hexdigest(), 'size_bytes': len(source)}:
            raise SystemExit('required recovery member binding mismatch: ' + name)
    if hashlib.sha256(archive.read(supervisor_name)).hexdigest() != '4daed58001f95c474b633191454b1a664dce2596e676d4f701188c9c2b240e83':
        raise SystemExit('repaired output guard fingerprint changed')
    authorization = json.loads(archive.read(authorization_name))
    if (authorization.get('failed_job_id') != '228078'
            or authorization.get('authorized_basin_id') != '01047000'
            or authorization.get('maximum_new_submissions') != 1
            or authorization.get('second_basin_authorized') is not False
            or authorization.get('formal_evaluation_authorized') is not False
            or authorization.get('automatic_retry_or_requeue_authorized') is not False
            or authorization.get('remote_phase') != remote_phase.as_posix()):
        raise SystemExit('recovery authorization identity changed')
    deploy_source = archive.read(deploy_name)

queue = subprocess.run(
    ['squeue', '-u', 'sunyiq', '-h', '-o', '%i|%j|%T'],
    check=True, text=True, capture_output=True, timeout=30,
).stdout
for line in queue.splitlines():
    fields = line.split('|')
    if len(fields) != 3:
        raise SystemExit('own scheduler queue format changed; no submit')
    if fields[1].startswith('tukf09-noise-'):
        raise SystemExit('another noise-stage job is pending or running; no submit')

sys.argv = [deploy_name, '--first', archive_sha, manifest_sha]
exec(compile(deploy_source, deploy_name, 'exec'), {'__name__': '__main__', '__file__': deploy_name})
PY
