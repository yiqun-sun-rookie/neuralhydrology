#!/usr/bin/env bash
# Authorized startup recovery probe; no deployment, training or tensor access.
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate knet_clean || { echo CONDA_FAILED; exit 1; }
set -u
python -I -B - <<'PY'
import datetime
import importlib.metadata
import json
import os
import pathlib
import platform
import subprocess
import sys

root = pathlib.Path('/data1/home/sunyiq/kalmannet_wrr_model_selection_20260908')
assert root.is_dir() and root.resolve() == root
target = root / 'stages/B'
argv = ['squeue', '-r', '-h', '-u', 'sunyiq', '-o', '%i|%T|%Z']
response = subprocess.run(argv, capture_output=True, text=True, check=False, timeout=45)
active = []
for line in response.stdout.splitlines():
    fields = line.split('|')
    assert len(fields) == 3
    if fields[2] == str(root) or fields[2].startswith(str(root) + '/'):
        active.append({'job_id': fields[0], 'state': fields[1], 'workdir': fields[2]})
versions = {'python_version': platform.python_version(),
            'numpy_version': importlib.metadata.version('numpy'),
            'torch_version': importlib.metadata.version('torch')}
report = {'kind': 'READ_ONLY_ACTIVATION_RECOVERY_PROBE',
          'observed_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'versions': versions, 'conda_prefix': os.environ.get('CONDA_PREFIX'),
          'python_isolated': bool(sys.flags.isolated), 'dont_write_bytecode': sys.dont_write_bytecode,
          'MKL_INTERFACE_LAYER': os.environ.get('MKL_INTERFACE_LAYER'),
          'stage_B_exists': os.path.lexists(target), 'active_family_jobs': active,
          'scheduler_query': {'command': argv, 'returncode': response.returncode,
                              'stdout': response.stdout, 'stderr': response.stderr},
          'deployment_or_training_executed': False, 'tensors_loaded': False, 'new_jobs_submitted': 0}
print(json.dumps(report, sort_keys=True), flush=True)
assert versions == {'python_version': '3.11.13', 'numpy_version': '2.3.3', 'torch_version': '2.4.0'}
assert report['conda_prefix'] == '/data1/home/sunyiq/miniconda3/envs/knet_clean'
assert report['MKL_INTERFACE_LAYER'] == 'LP64,GNU'
assert report['python_isolated'] and report['dont_write_bytecode']
assert response.returncode == 0 and not response.stderr and not active and not os.path.lexists(target)
PY
