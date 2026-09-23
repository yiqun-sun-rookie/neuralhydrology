#!/bin/bash
set -euo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -I -B - <<'METADATA_ONLY'
import base64, hashlib, json
from pathlib import Path
old = Path('/data1/home/sunyiq/zhenjiang_shared_base_no_training_time_cap_20260917_001')
new = Path('/data1/home/sunyiq/zhenjiang_update_budget_20260922_001')
paths = [old/'preflight/preparation.json', old/'preflight/result.json', old/'train/result.json', new/'run/complete.json', new/'run/result.json']
paths += [new/'run'/('seed_'+str(seed))/stage/'epoch_20_identity.json'
          for seed in (17,29,43) for stage in ('rolling_encoder','differentiable_filter')]
if (new/'run/failure.json').exists():
    raise ValueError('Training failure exists')
rows = []
total = 0
for path in paths:
    if path.is_symlink() or not path.is_file() or not 0 < path.stat().st_size <= 100000:
        raise ValueError('Metadata path or bound differs: '+str(path))
    raw = path.read_bytes()
    json.loads(raw)
    total += len(raw)
    if total > 250000:
        raise ValueError('Metadata total bound exceeded')
    rows.append({'path':str(path), 'bytes':len(raw), 'sha256':hashlib.sha256(raw).hexdigest(), 'base64':base64.b64encode(raw).decode()})
print(json.dumps({'status':'metadata_only', 'files':rows, 'total_bytes':total}, sort_keys=True))
METADATA_ONLY
