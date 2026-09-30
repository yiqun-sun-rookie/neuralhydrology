#!/bin/bash
set -euo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -I -B - <<'ZJ_TARGET_PROBE'
import hashlib
import json
import os
from pathlib import Path
import subprocess
root = Path('/data1/home/sunyiq/zhenjiang_target_state_diagnostic_20260930_001')
parent = Path('/data1/home/sunyiq/zhenjiang_architecture_sharing_20260929_001')
if os.path.lexists(root):
    raise SystemExit('new exclusive diagnostic root is occupied')
registry = parent / 'registry_frozen.json'
if hashlib.sha256(registry.read_bytes()).hexdigest() != 'bbb07af90473ba1136043eceaa5a09bb6d085db172d7e37e1fe9a185e11179bf':
    raise SystemExit('registered parent experiment changed')
document = json.loads(registry.read_bytes())
for item in document['training_sources']:
    path = parent / item['relative_path']
    if path.is_symlink() or not path.is_file() or path.stat().st_size != item['size_bytes']:
        raise SystemExit('registered parent training input unavailable')
answers = {}
for key, argv in [('partition', ['scontrol', 'show', 'partition', 'hgpu2p', '-o']),
                  ('nodes', ['sinfo', '-p', 'hgpu2p', '-N', '-h', '-o', '%N|%t|%G'])]:
    reply = subprocess.run(argv, capture_output=True, text=True, timeout=15, check=False)
    if reply.returncode or len(reply.stdout.encode()) > 12000:
        raise SystemExit('bounded cluster resource query failed: ' + key)
    answers[key] = reply.stdout
print(json.dumps({'status': 'PASS_READ_ONLY_EXCLUSIVE_ROOT_PROBE',
                  'new_root_absent': True, 'parent_registry_verified': True,
                  'parent_registered_inputs': 10, 'resources': answers}, sort_keys=True))
ZJ_TARGET_PROBE
