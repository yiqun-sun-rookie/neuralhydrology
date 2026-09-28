#!/usr/bin/env bash
set -euo pipefail
export PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1
export OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1
export MKL_THREADING_LAYER=GNU MKL_SERVICE_FORCE_INTEL=1 CUDA_VISIBLE_DEVICES='' CUDA_CACHE_DISABLE=1
export PYTHONPATH=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r14_20260909/runtime_v2r14/pysite

printf '=== ONE AUTHORIZED 20-STATE FULL-BUDGET SUBMISSION ===\n'
/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python -B - \
  174e6203f4556d2845ee68cde0a82b95cdf930ec979c380aac93e0537e3f25ac \
  4ebee2dcbd215e9751c86ca9895b84090956e7857d84b524fc87d60a3ea6afa1 \
  baee8a0485fd600b329457236f39ce29ee4db6112b456ee6e6591d12349a1d14 <<'PY'
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import zipfile

archive_sha, manifest_sha, first_admission_sha = sys.argv[1:]
archive_path = Path('/data1/home/sunyiq/hpc_mailbox/inbox/kalmannet-tukf09-noise-20260922/payload/full_budget_01142500_20260928_attempt1.zip')
remote_phase = Path('/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/full_budget_01142500_20260928_attempt1')
if remote_phase.exists() or remote_phase.is_symlink():
    raise SystemExit('exclusive 20-state phase already exists; no submission')
if not archive_path.is_file() or archive_path.is_symlink():
    raise SystemExit('one 20-state payload missing or linked; no submission')
with archive_path.open('rb') as stream:
    if hashlib.file_digest(stream, 'sha256').hexdigest() != archive_sha:
        raise SystemExit('one 20-state package fingerprint mismatch; no submission')
with zipfile.ZipFile(archive_path) as archive:
    names = archive.namelist()
    if len(names) != len(set(names)) or len(names) != 326 or names.count('bundle_manifest.json') != 1:
        raise SystemExit('one 20-state package membership ambiguous; no submission')
    manifest_raw = archive.read('bundle_manifest.json')
    if hashlib.sha256(manifest_raw).hexdigest() != manifest_sha:
        raise SystemExit('one 20-state manifest fingerprint mismatch; no submission')
    manifest = json.loads(manifest_raw)
    if manifest.get('path_mapping', {}).get('remote_root') != remote_phase.as_posix() + '/bundle':
        raise SystemExit('one 20-state remote root changed; no submission')
    deploy_name = 'hpc/tukf09_two_basin_full_budget_deploy_v2.py'
    authorization_name = 'hpc/tukf09_one_20_state_full_budget_authorization_v1.json'
    first_admission_name = 'input/first_basin_formal_admission.json'
    for name in (deploy_name, authorization_name, first_admission_name,
                 'hpc/tukf09_two_basin_full_budget_job_v2.slurm',
                 'hpc/tukf09_two_basin_hpc_supervisor_v1.py'):
        if names.count(name) != 1 or name not in manifest.get('files', {}):
            raise SystemExit('one 20-state required member missing: ' + name)
        data = archive.read(name)
        if manifest['files'][name] != {'sha256': hashlib.sha256(data).hexdigest(), 'size_bytes': len(data)}:
            raise SystemExit('one 20-state required member record mismatch: ' + name)
    if hashlib.sha256(archive.read(first_admission_name)).hexdigest() != first_admission_sha:
        raise SystemExit('first-basin admission fingerprint mismatch; no submission')
    authorization = json.loads(archive.read(authorization_name))
    if (authorization.get('authorized_basin_id') != '01142500'
            or authorization.get('maximum_new_submissions') != 1
            or authorization.get('first_basin_formal_admission_sha256') != first_admission_sha
            or authorization.get('formal_local_selection_candidate_authorized') is not True
            or authorization.get('other_basin_submission_authorized') is not False
            or authorization.get('formal_evaluation_authorized') is not False
            or authorization.get('automatic_retry_or_requeue_authorized') is not False
            or authorization.get('remote_phase') != remote_phase.as_posix()):
        raise SystemExit('one 20-state authorization changed; no submission')
    deploy_source = archive.read(deploy_name)
    if b'EXECUTABLE_BASINS = ("01142500",)' not in deploy_source:
        raise SystemExit('deployer basin guard changed; no submission')

queue = subprocess.run(
    ['squeue', '-u', 'sunyiq', '-h', '-o', '%i|%j|%T'],
    check=True, text=True, capture_output=True, timeout=30,
).stdout
for line in queue.splitlines():
    fields = line.split('|')
    if len(fields) != 3:
        raise SystemExit('own queue format changed; no submission')
    if fields[1].startswith('tukf09-noise-'):
        raise SystemExit('another noise-stage job exists; no submission')

sys.argv = [deploy_name, '--first', archive_sha, manifest_sha]
exec(compile(deploy_source, deploy_name, 'exec'), {'__name__': '__main__', '__file__': deploy_name})
PY
