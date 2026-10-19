#!/bin/bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - <<'FB'
"""Read-only: per-model list of basins whose slots failed with a baseline-reproduction error. No mutation."""
import json, re, datetime, collections
from pathlib import Path
E = Path('/data1/home/sunyiq/hydrol85935_revision_20261008_001/execution/hpc_v009/records')
rows = []
for l in (E / 'ledger.jsonl').read_bytes().split(b'\n'):
    try: v = json.loads(l.decode('utf8', 'replace'))
    except Exception: continue
    if v.get('status') == 'failed': rows.append(v)
model = lambda c: re.match(r'(original_s\d+|single_temperature_s\d+)', c)[1]
per = collections.defaultdict(dict)
other = []
for r in rows:
    m = re.search(r'Baseline reproduction failed: NSE difference=([0-9.e+-]+), max prediction error=([0-9.e+-]+)', r.get('reason', ''))
    if m: per[model(r['combination_id'])].setdefault(r['basin_id'], dict(nse_diff=float(m[1]), max_err=float(m[2]), combos=0))['combos'] += 1
    else: other.append(dict(model=model(r['combination_id']), basin=r['basin_id'], combo=r['combination_id'], reason=r.get('reason', '')[:120]))
print('FB_TIME ' + json.dumps(dict(utc=datetime.datetime.now(datetime.timezone.utc).isoformat(), failed_rows=len(rows))), flush=True)
print('FB_BASELINE ' + json.dumps({m: d for m, d in per.items()}), flush=True)
print('FB_OTHER ' + json.dumps(other), flush=True)
FB
