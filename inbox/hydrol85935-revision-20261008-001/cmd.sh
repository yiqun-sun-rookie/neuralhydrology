#!/bin/bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - <<'F2'
"""Read-only tolerant diagnosis: bad ledger line, failure reasons, failed element logs. No mutation."""
import json, collections, datetime
from pathlib import Path
R = Path('/data1/home/sunyiq/hydrol85935_revision_20261008_001'); E = R / 'execution/hpc_v009/records'
def emit(k, v): print(k + ' ' + json.dumps(v, ensure_ascii=True), flush=True)
emit('D5_TIME', dict(utc=datetime.datetime.now(datetime.timezone.utc).isoformat()))
raw = (E / 'ledger.jsonl').read_bytes(); lines = raw.split(b'\n')
rows, bad = [], []
for i, l in enumerate(lines, 1):
    if not l.strip(): continue
    try: rows.append((i, json.loads(l.decode('utf8', 'replace'))))
    except Exception as ex: bad.append(i)
for i in bad:
    emit('D5_BADLINE', dict(line=i, length=len(lines[i - 1]), head=lines[i - 1][:400].decode('utf8', 'replace'), tail=lines[i - 1][-300:].decode('utf8', 'replace'),
         before=lines[i - 2][:300].decode('utf8', 'replace'), after=lines[i][:300].decode('utf8', 'replace') if i < len(lines) else ''))
failed = [(i, r) for i, r in rows if r.get('status') == 'failed']
def key(r): return str(r.get('error') or r.get('reason') or r.get('message') or '')[:200]
emit('D5_FAIL_KEYS', sorted({k for _, r in failed for k in r}))
emit('D5_FAIL_REASONS', dict(collections.Counter(key(r) for _, r in failed)))
new = [(i, r) for i, r in failed if i > 4000]
emit('D5_NEW_FAIL_BY_BASIN', dict(collections.Counter(r['basin_id'] for _, r in new)))
emit('D5_NEW_FAIL_BY_COMBO', dict(collections.Counter(r['combination_id'] for _, r in new)))
emit('D5_NEW_FAIL_SAMPLE', [r for _, r in new[:2]])
for e in (23,):
    for suf in ('err', 'out'):
        p = R / f'control/hybrid_v009_20261012_001/logs/attacks-241336_{e}.{suf}'
        if p.exists():
            b = p.read_bytes(); emit('D5_LOG', dict(element=e, kind=suf, bytes=len(b), tail=b[-2500:].decode('utf8', 'replace') if suf == 'err' or len(b) < 1400 else b[-900:].decode('utf8', 'replace')))
F2
