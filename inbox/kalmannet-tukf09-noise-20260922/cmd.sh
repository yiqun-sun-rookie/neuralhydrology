#!/usr/bin/env bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1

/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python -B - 9e428c321ef1cddbf39c016cb048198d4ecb012e3e1ef37b479556359edea599 ad840ffd9959505a31686dc3f255947b1dae2a45bab33ef24de0e97e04fc4f08 <<'PY'
import hashlib
import sys
import zipfile
from pathlib import Path

archive_sha, manifest_sha = sys.argv[1:]
for value in (archive_sha, manifest_sha):
    if len(value) != 64 or any(char not in '0123456789abcdef' for char in value):
        raise SystemExit('unfilled or invalid fingerprint placeholder')

archive_path = Path('/data1/home/sunyiq/hpc_mailbox/inbox/kalmannet-tukf09-noise-20260922/payload/narrow_probe_v1.zip')
with archive_path.open('rb') as stream:
    if hashlib.file_digest(stream, 'sha256').hexdigest() != archive_sha:
        raise SystemExit('archive fingerprint mismatch')

deploy_name = 'hpc/tukf09_two_basin_hpc_deploy_v1.py'
with zipfile.ZipFile(archive_path) as archive:
    if archive.namelist().count(deploy_name) != 1:
        raise SystemExit('deploy member missing or duplicated')
    deploy_source = archive.read(deploy_name)

sys.argv = [deploy_name, archive_sha, manifest_sha]
exec(compile(deploy_source, deploy_name, 'exec'), {'__name__': '__main__', '__file__': deploy_name})
PY
