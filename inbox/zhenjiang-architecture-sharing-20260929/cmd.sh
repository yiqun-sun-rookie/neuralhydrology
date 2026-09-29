#!/bin/bash
set -euo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -I -B - <<'ZJ_ARCH_READONLY'
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat

root = Path('/data1/home/sunyiq/zhenjiang_architecture_sharing_20260929_001')
receipt_path = root / 'deploy/deployment.json'
raw = receipt_path.read_bytes()
receipt = json.loads(raw)
binding = {'device': root.stat().st_dev, 'inode': root.stat().st_ino,
           'uid': root.stat().st_uid,
           'mode': stat.S_IMODE(root.stat().st_mode)}
job = root / 'deploy/job.sh'
directives = [line for line in job.read_text().splitlines()
              if line.startswith('#SBATCH ')]
status = {
    'root': str(root),
    'root_is_private': not root.is_symlink() and binding['mode'] == 0o700,
    'root_binding_matches': binding == receipt['root_binding'],
    'deployment_sha256': hashlib.sha256(raw).hexdigest(),
    'status': receipt['status'],
    'source_files': receipt['registered_training_inputs'],
    'job_sha256_matches': hashlib.sha256(job.read_bytes()).hexdigest() == receipt['job_sha256'],
    'resource_directives': directives,
    'submission_exists': os.path.lexists(root / 'submission'),
    'runs_exists': os.path.lexists(root / 'runs'),
    'sbatch_executable': shutil.which('sbatch'),
    'xbatch_executable': shutil.which('xbatch'),
    'campus_xbatch_exists': Path('/usr/local/globle/softs/slurm/19.05.4.1/bin/xbatch').is_file(),
}
print(json.dumps(status, sort_keys=True))
if (not status['root_is_private'] or not status['root_binding_matches']
        or not status['job_sha256_matches']
        or status['status'] != 'DEPLOYED_NO_TRAINING'
        or status['source_files'] != 10
        or status['submission_exists'] or status['runs_exists']):
    raise SystemExit('pre-submission read-only identity check failed')
ZJ_ARCH_READONLY
