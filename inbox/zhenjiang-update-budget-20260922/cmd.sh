#!/bin/bash
set -euo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -I -B - <<'ZHENJIANG_GATE_READ'
import hashlib
import json
from pathlib import Path

root = Path('/data1/home/sunyiq/zhenjiang_update_budget_20260922_001')
directory = root / 'run' / 'seed_17' / 'rolling_encoder'
def read(name):
    path = directory / name
    if path.is_symlink() or not path.is_file() or path.stat().st_size > 16384:
        raise ValueError('expected bounded gate record absent')
    raw = path.read_bytes()
    return json.loads(raw), hashlib.sha256(raw).hexdigest()

gate, gate_sha = read('epoch_20_identity.json')
epoch, epoch_sha = read('epoch_20.json')
print(json.dumps({'job_id': '227320', 'seed': 17,
                  'stage': 'rolling_encoder',
                  'gate_status': gate.get('status'),
                  'gate_sha256': gate_sha,
                  'old_best_epoch': gate.get('old_best_epoch'),
                  'old_best_score_m': gate.get('old_best_score_m'),
                  'old_best_state_sha256': gate.get('old_best_state_sha256'),
                  'old_final_checkpoint': gate.get('old_final_checkpoint'),
                  'epoch_20_record_sha256': epoch_sha,
                  'epoch_20_best_epoch': epoch.get('best_epoch'),
                  'epoch_20_best_score_m': epoch.get('best_score_m')},
                 sort_keys=True))
ZHENJIANG_GATE_READ
