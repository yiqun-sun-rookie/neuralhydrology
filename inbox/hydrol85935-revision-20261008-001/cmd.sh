#!/bin/bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - <<'F12'
"""Read-only diagnosis of failed array element 241336_12 and new ledger failures. No mutation."""
import json, subprocess, datetime, collections, hashlib
from pathlib import Path
R = Path('/data1/home/sunyiq/hydrol85935_revision_20261008_001'); E = R / 'execution/hpc_v009/records'
def emit(k, v): print(k + ' ' + json.dumps(v), flush=True)
emit('F12_TIME', dict(utc=datetime.datetime.now(datetime.timezone.utc).isoformat()))
logs = sorted((R / 'control/hybrid_v009_20261012_001/logs').glob('attacks-241336_1[0-4].*'))
for p in logs:
    b = p.read_bytes(); emit('F12_LOG', dict(path=str(p), bytes=len(b), tail=b[-5000:].decode('utf8', 'replace')))
st = sorted((R / 'control/hybrid_v028_20261014_001/stage_results').glob('attacks_1[0-4]_*.json'))
for p in st: emit('F12_STAGE', dict(path=str(p), value=json.loads(p.read_text())))
rows = [json.loads(l) for l in (E / 'ledger.jsonl').read_text().splitlines() if l.strip()]
failed = [r for r in rows if r['status'] == 'failed']
emit('F12_FAILED_SUMMARY', dict(total=len(failed), by_reason=dict(collections.Counter(str(r.get('error', r.get('reason', '')))[:160] for r in failed)),
     by_basin=dict(collections.Counter(r['basin_id'] for r in failed).most_common(12)), keys=sorted(failed[-1].keys())))
emit('F12_FAILED_TAIL', failed[-3:])
done = {(r['combination_id'], r['basin_id']) for r in rows if r['status'] in ('complete', 'reused')}
markers = {(p.parent.parent.name, p.parent.name) for p in (E / 'attacks').glob('*/*/complete.json')}
miss = sorted(markers - done)
emit('F12_MISSING', [dict(slot=m, files=sorted(x.name for x in (E / 'attacks' / m[0] / m[1]).iterdir()),
     mtime=(E / 'attacks' / m[0] / m[1] / 'complete.json').stat().st_mtime) for m in miss])
emit('F12_TASKS', [dict(job=j, r=subprocess.run(['sacct', '-X', '-j', j, '-n', '-P', '-o', 'JobID,State,ExitCode,Elapsed,NodeList,Start,End'], capture_output=True, text=True).stdout) for j in ('241336_12',)])
F12
