#!/bin/bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - <<'APPLY'
"""Raise the ArrayTaskThrottle of parent main array 241336 from 1 to 2 (scheduler setting only)."""
import json, subprocess, datetime, hashlib, os
from pathlib import Path
R = Path('/data1/home/sunyiq/hydrol85935_revision_20261008_001')
D = R / 'control/two_gpu_20261017_001'
def emit(k, v): print(k + ' ' + json.dumps(v), flush=True)
def run(a): return subprocess.run(a, capture_output=True, text=True, timeout=60)
def now(): return datetime.datetime.now(datetime.timezone.utc).isoformat()
def write(p, v):
    p.parent.mkdir(parents=True, exist_ok=True)
    with p.open('x') as f: json.dump(v, f, indent=2); f.write('\n'); f.flush(); os.fsync(f.fileno())
assert not (D / 'apply.intent.json').exists(), 'already attempted; reconcile, never repeat'
before = run(['scontrol', 'show', 'job', '-o', '241336']).stdout
assert 'ArrayTaskThrottle=1 ' in before or before.rstrip().endswith('ArrayTaskThrottle=1') or 'ArrayTaskThrottle=1' in before.split(), before[:300]
cmd = str(R / 'control/hybrid_v009_20261012_001/attacks.sbatch')
assert 'Command=' + cmd in before and 'NumCPUs=4' in before and 'gpu:1' in before and 'Partition=hgpu2p' in before, before[:600]
ledger = R / 'execution/hpc_v009/records/ledger.jsonl'
rows = ledger.read_text().splitlines(); bad = sum(1 for l in rows if not l.strip().startswith('{') or not l.strip().endswith('}'))
write(D / 'baseline.json', dict(utc=now(), ledger_lines=len(rows), ledger_nonjson_lines=bad, ledger_sha256=hashlib.sha256(ledger.read_bytes()).hexdigest(), job_line=before))
write(D / 'apply.intent.json', dict(utc=now(), command=['scontrol', 'update', 'JobId=241336', 'ArrayTaskThrottle=2']))
r = run(['scontrol', 'update', 'JobId=241336', 'ArrayTaskThrottle=2'])
write(D / 'apply.result.json', dict(utc=now(), returncode=r.returncode, stdout=r.stdout, stderr=r.stderr))
assert r.returncode == 0, r.stderr
after = run(['scontrol', 'show', 'job', '-o', '241336']).stdout
emit('THROTTLE_APPLIED', dict(throttle_before=1, throttle_after=2 if 'ArrayTaskThrottle=2' in after else None, returncode=r.returncode, stderr=r.stderr,
     command_unchanged=('Command=' + cmd) in after, baseline=json.loads((D / 'baseline.json').read_text())['ledger_lines']))
emit('THROTTLE_QUEUE', run(['squeue', '-h', '-r', '-j', '241336', '-o', '%i|%T|%r']).stdout.splitlines()[:6])
assert 'ArrayTaskThrottle=2' in after
APPLY
