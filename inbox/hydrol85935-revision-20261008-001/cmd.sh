#!/bin/bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - <<'REPAIR'
"""1) Back to one concurrent array element (ledger appends from two writers tear lines on this filesystem).
2) Same-length in-place repair of the single torn ledger fragment; no line is removed or re-ordered, file length unchanged.
Evidence copy and hashes are written first. Idempotent guard: refuses to run twice."""
import hashlib, json, os, shutil, subprocess, datetime
from pathlib import Path
R = Path('/data1/home/sunyiq/hydrol85935_revision_20261008_001'); E = R / 'execution/hpc_v009/records'; L = E / 'ledger.jsonl'
D = R / 'control/ledger_repair_20261018_001'
def emit(k, v): print(k + ' ' + json.dumps(v, ensure_ascii=True), flush=True)
def now(): return datetime.datetime.now(datetime.timezone.utc).isoformat()
def run(a): r = subprocess.run(a, capture_output=True, text=True, timeout=60); return dict(returncode=r.returncode, stdout=r.stdout, stderr=r.stderr)
def write(p, v):
    with p.open('x') as f: json.dump(v, f, indent=2); f.write('\n'); f.flush(); os.fsync(f.fileno())
D.mkdir(exist_ok=False)  # second run fails here
# --- throttle first: stops further interleaved appends
before = run(['scontrol', 'show', 'job', '-o', '241336']).get('stdout', '')
assert 'ArrayTaskThrottle=2' in before and f'Command={R}/control/hybrid_v009_20261012_001/attacks.sbatch' in before
write(D / 'throttle.intent.json', dict(utc=now(), command=['scontrol', 'update', 'JobId=241336', 'ArrayTaskThrottle=1']))
t = run(['scontrol', 'update', 'JobId=241336', 'ArrayTaskThrottle=1']); write(D / 'throttle.result.json', dict(utc=now(), **t))
after = run(['scontrol', 'show', 'job', '-o', '241336'])['stdout']
emit('R_THROTTLE', dict(returncode=t['returncode'], stderr=t['stderr'], throttle_after_1='ArrayTaskThrottle=1' in after and 'ArrayTaskThrottle=2' not in after))
assert t['returncode'] == 0
# --- evidence copy of the whole ledger (read once; later appends continue untouched)
snap = L.read_bytes(); shutil.copyfile(L, D / 'ledger_before_repair.jsonl')
copied = (D / 'ledger_before_repair.jsonl').read_bytes()
emit('R_EVIDENCE', dict(bytes=len(snap), sha256=hashlib.sha256(snap).hexdigest(), copy_equal=snap == copied[:len(snap)] or copied == snap))
# --- locate torn fragment lines in the first len(snap) bytes (a complete record never starts with a quote)
offset, bad = 0, []
for line in snap.split(b'\n')[:-1]:
    try: json.loads(line.decode('utf8'))
    except Exception: bad.append((offset, line))
    offset += len(line) + 1
emit('R_BAD', [dict(offset=o, line=l.decode('utf8', 'replace')) for o, l in bad])
assert len(bad) == 1 and bad[0][1] == b'"}', 'unexpected ledger damage; stop for review'
off = bad[0][0]
with L.open('r+b') as f:
    f.seek(off - 1); assert f.read(4) == b'\n"}\n', 'bytes around fragment changed'
    f.seek(off); f.write(b'{}'); f.flush(); os.fsync(f.fileno())
now_bytes = L.read_bytes()
assert now_bytes[:off] == snap[:off] and now_bytes[off + 2:len(snap)] == snap[off + 2:], 'repair touched other bytes'
rows = [json.loads(l) for l in now_bytes.split(b'\n') if l.strip()]
emit('R_DONE', dict(offset=off, replaced='"}', with_='{}', length_unchanged=len(now_bytes) >= len(snap), parsed_rows=len(rows), empty_marker_rows=sum(1 for r in rows if r == {}),
     status=dict(__import__('collections').Counter(r.get('status') for r in rows if r))))
write(D / 'repair_record.json', dict(utc=now(), offset=off, replaced=['"}'], with_=['{}'], evidence=str(D / 'ledger_before_repair.jsonl'), before_sha256=hashlib.sha256(snap).hexdigest(),
      note='Fragment left when a 3-byte-longer record (12375900 physical_range, status complete) was overwritten by another writer; that complete record is derivable from its complete.json marker and audit_all classifies complete slots from markers, so no ledger line is needed.'))
REPAIR
