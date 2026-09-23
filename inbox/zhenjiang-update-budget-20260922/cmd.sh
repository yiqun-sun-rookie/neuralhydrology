#!/bin/bash
set -euo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -I -B - <<'ZHENJIANG_CURVES'
import hashlib
import json
import math
from pathlib import Path

root = Path('/data1/home/sunyiq/zhenjiang_update_budget_20260922_001/run')
complete = root / 'complete.json'
if complete.is_symlink() or not complete.is_file():
    raise ValueError('formal completion record absent')
if json.loads(complete.read_bytes()).get('status') != 'complete':
    raise ValueError('run is not formally complete')

curves = {}
sources = {}
for seed in (17, 29, 43):
    for stage in ('rolling_encoder', 'differentiable_filter'):
        key = str(seed) + '/' + stage
        values = []
        hashes = []
        for epoch in range(101):
            path = root / ('seed_' + str(seed)) / stage / ('epoch_' + str(epoch) + '.json')
            if path.is_symlink() or not path.is_file() or not 0 < path.stat().st_size <= 16384:
                raise ValueError('bounded epoch record absent: ' + key + '/' + str(epoch))
            raw = path.read_bytes()
            row = json.loads(raw)
            value = float(row['score_m'])
            if row['epoch'] != epoch or not math.isfinite(value) or value < 0:
                raise ValueError('epoch identity or score differs')
            values.append(value)
            hashes.append(hashlib.sha256(raw).hexdigest())
        curves[key] = values
        sources[key] = hashlib.sha256(''.join(hashes).encode()).hexdigest()

payload = {'job_id': '227320', 'metric': '2022 development weighted mean absolute error in metres',
           'epochs': list(range(101)), 'curves': curves,
           'source_epoch_hash_chain_sha256': sources}
canonical = json.dumps(payload, sort_keys=True, separators=(',', ':'), allow_nan=False)
print(json.dumps({'payload': payload, 'payload_sha256': hashlib.sha256(canonical.encode()).hexdigest()},
                 sort_keys=True))
ZHENJIANG_CURVES
