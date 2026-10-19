#!/bin/bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - <<'CHECK'
"""Read-only: concurrency integrity of the shared ledger plus element/GPU state. No mutation."""
import json, subprocess, datetime, hashlib, collections
from pathlib import Path
R = Path('/data1/home/sunyiq/hydrol85935_revision_20261008_001'); E = R / 'execution/hpc_v009/records'
def emit(k, v): print(k + ' ' + json.dumps(v), flush=True)
def run(a):
    r = subprocess.run(a, capture_output=True, text=True, timeout=45); return dict(returncode=r.returncode, stdout=r.stdout[:12000], stderr=r.stderr[:800])
emit('LC_TIME', dict(utc=datetime.datetime.now(datetime.timezone.utc).isoformat()))
markers = {(p.parent.parent.name, p.parent.name) for p in (E / 'attacks').glob('*/*/complete.json')}  # markers first, ledger second: a record being written cannot look like a lost line
led = E / 'ledger.jsonl'; raw = led.read_bytes(); lines = raw.decode('utf8', 'replace').split('\n')
parsed, bad = [], []
for i, l in enumerate(lines):
    if not l.strip(): continue
    try:
        v = json.loads(l)
        if v == {}: continue  # repaired torn fragment (ledger_repair_20261018_001)
        assert isinstance(v, dict) and {'basin_id', 'combination_id', 'status'} <= set(v); parsed.append(v)
    except Exception: bad.append(i + 1)
status = collections.Counter(v['status'] for v in parsed)
slot_lines = collections.Counter((v['combination_id'], v['basin_id']) for v in parsed if v['status'] in ('complete', 'reused'))
missing = sorted(markers - set(slot_lines))
emit('LC_LEDGER', dict(lines=len(parsed), unparsable_line_numbers=bad[:20], unparsable=len(bad), bytes=len(raw), ends_with_newline=raw.endswith(b'\n'), status=dict(status),
     markers=len(markers), markers_without_ledger_line=len(missing), missing_head=missing[:10],
     slots_with_more_than_one_complete_line=sum(1 for v in slot_lines.values() if v > 1)))
emit('LC_ELEMENTS', run(['sacct', '-X', '-j', '241336', '-n', '-P', '-o', 'JobID,State,ExitCode,Elapsed,Start,End,NodeList', '--starttime', '2026-10-17T21:11:00']))
emit('LC_RUNNING', run(['squeue', '-h', '-r', '-u', 'sunyiq', '-t', 'RUNNING', '-O', 'jobid:16,partition:10,reason:12,tres-per-node:14,nodelist:10,timeused:12']))
emit('LC_PENDING_MAIN', run(['squeue', '-h', '-r', '-j', '241336', '-t', 'PENDING', '-O', 'jobid:16,reason:24,starttime:22']))
emit('LC_HGPU2P', run(['sinfo', '-N', '-h', '-p', 'hgpu2p', '-O', 'nodelist:12,statelong:12,gresused:26']))
CHECK
