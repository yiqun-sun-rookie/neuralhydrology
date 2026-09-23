#!/usr/bin/env bash
set -eo pipefail
export PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1
export OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1
export MKL_THREADING_LAYER=GNU MKL_SERVICE_FORCE_INTEL=1 CUDA_VISIBLE_DEVICES='' CUDA_CACHE_DISABLE=1
export PYTHONPATH=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r14_20260909/runtime_v2r14/pysite

/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python -B - \
  724e7d8816aad8ce9b83775e21130645e066cc61e1488bf349f3429d8b0b431d \
  03efc5f263779b6341e9580bc8cde42308adf9e816247ebaa235431d91996662 <<'PY'
import hashlib
import json
from pathlib import Path
import sys
import zipfile

archive_sha, manifest_sha = sys.argv[1:]
archive_path = Path('/data1/home/sunyiq/hpc_mailbox/inbox/kalmannet-tukf09-noise-20260922/payload/full_budget_v2r4.zip')
with archive_path.open('rb') as stream:
    if hashlib.file_digest(stream, 'sha256').hexdigest() != archive_sha:
        raise SystemExit('full-budget payload fingerprint mismatch')
with zipfile.ZipFile(archive_path) as archive:
    names = archive.namelist()
    if len(names) != len(set(names)) or names.count('bundle_manifest.json') != 1:
        raise SystemExit('full-budget payload membership is duplicated or incomplete')
    manifest_raw = archive.read('bundle_manifest.json')
    if hashlib.sha256(manifest_raw).hexdigest() != manifest_sha:
        raise SystemExit('full-budget manifest fingerprint mismatch')
    manifest = json.loads(manifest_raw)
    deploy_name = 'hpc/tukf09_two_basin_full_budget_deploy_v2.py'
    if names.count(deploy_name) != 1 or deploy_name not in manifest.get('files', {}):
        raise SystemExit('full-budget deploy member is missing or ambiguous')
    deploy_source = archive.read(deploy_name)
    record = manifest['files'][deploy_name]
    if record != {'sha256': hashlib.sha256(deploy_source).hexdigest(), 'size_bytes': len(deploy_source)}:
        raise SystemExit('full-budget deploy member binding mismatch')

sys.argv = [deploy_name, '--first', archive_sha, manifest_sha]
exec(compile(deploy_source, deploy_name, 'exec'), {'__name__': '__main__', '__file__': deploy_name})
PY
