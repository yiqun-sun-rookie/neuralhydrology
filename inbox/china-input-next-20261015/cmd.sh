#!/bin/bash
set -eo pipefail
umask 077
export PYTHONDONTWRITEBYTECODE=1 CUDA_VISIBLE_DEVICES=''
exec timeout --signal=TERM --kill-after=3s 20s /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'HPC_READINESS'
"""Lightweight login-node metadata only: never read credentials or run scientific code."""
import base64
import datetime
import hashlib
import importlib.metadata
import importlib.util
import json
import os
from pathlib import Path
import time
import zlib

BEGAN = time.monotonic()
packages = []
for module, distribution in [('ee', 'earthengine-api'), ('google.auth', 'google-auth'),
                             ('googleapiclient', 'google-api-python-client'), ('requests', 'requests')]:
    try:
        found = importlib.util.find_spec(module) is not None
        version = importlib.metadata.version(distribution) if found else None
        packages.append(dict(module=module, distribution=distribution, found=found, version=version))
    except Exception as error:
        packages.append(dict(module=module, distribution=distribution, found=None, version=None,
                             error_type=type(error).__name__))
home = Path.home()
credentials = []
for alias, relative in [('earthengine_default', '.config/earthengine/credentials'),
                        ('google_adc_default', '.config/gcloud/application_default_credentials.json')]:
    path = home / relative
    try:
        # No resolve, open, read, hashing, or serialization of any credential content.
        present = path.exists()
        symbolic = path.is_symlink()
        regular = path.is_file() if present and not symbolic else False
        size = path.stat().st_size if regular else None
        credentials.append(dict(alias=alias, present=present, symbolic=symbolic, regular=regular, bytes=size))
    except Exception as error:
        credentials.append(dict(alias=alias, present=None, error_type=type(error).__name__))
value = dict(stage='CHINA_WEATHER_HPC_READINESS_20261020_V1',
             server_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
             packages=packages, credential_path_metadata=credentials,
             google_application_credentials_env_configured=bool(os.environ.get('GOOGLE_APPLICATION_CREDENTIALS')),
             authorization_validated=False, acquisition_running=False, credential_content_bytes_read=0,
             source_content_bytes_read=0, source_gets=0, slurm_submissions=0, model_calls=0,
             automatic_checks_enabled=False, seconds=time.monotonic() - BEGAN)
body = json.dumps(value, ensure_ascii=False, separators=(',', ':')).encode()
assert len(body) <= 65536 and time.monotonic() - BEGAN < 15
print('HPC_READINESS_BYTES=' + str(len(body)))
print('HPC_READINESS_SHA256=' + hashlib.sha256(body).hexdigest())
print('HPC_READINESS_ZLIB_BASE64=' + base64.b64encode(zlib.compress(body)).decode())
print('HPC_READINESS_DONE', flush=True)
assert time.monotonic() - BEGAN < 15

HPC_READINESS
