#!/bin/bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - <<'FS'
"""Read-only: filesystem type of the shared outputs, element states, ledger integrity. No mutation."""
import json, subprocess, datetime, hashlib
from pathlib import Path
def emit(k, v): print(k + ' ' + json.dumps(v), flush=True)
def q(label, args):
    try:
        r = subprocess.run(args, capture_output=True, text=True, timeout=40)
        emit(label, dict(args=args, returncode=r.returncode, stdout=r.stdout[:20000], stderr=r.stderr[:1500]))
    except Exception as ex:
        emit(label, dict(args=args, error=repr(ex)))
root = '/data1/home/sunyiq/hydrol85935_revision_20261008_001'
emit('FS_TIME', dict(utc=datetime.datetime.now(datetime.timezone.utc).isoformat()))
q('FS_STAT', ['stat', '-f', '-c', '%T %n', root, root + '/execution/hpc_v009/records'])
q('FS_DF', ['df', '-T', root])
q('FS_MOUNT', ['bash', '-c', 'mount | grep -E " /data1 | /data1/" | head -5'])
q('FS_ELEMENTS', ['sacct', '-X', '-j', '241336', '-n', '-P', '-o', 'JobID,State,ExitCode,Elapsed,Start,End,NodeList,AllocTRES', '--starttime', '2026-10-17T20:00:00'])
q('FS_SQUEUE_MAIN', ['squeue', '-h', '-r', '-j', '241336', '-O', 'jobid:16,state:10,reason:26,nodelist:10,timeused:12', ])
led = Path(root + '/execution/hpc_v009/records/ledger.jsonl')
rows = led.read_text().splitlines()
bad = 0
for l in rows:
    try: json.loads(l)
    except Exception: bad += 1
emit('FS_LEDGER', dict(lines=len(rows), unparsable=bad, bytes=led.stat().st_size, sha256=hashlib.sha256(led.read_bytes()).hexdigest()))
stage = sorted((Path(root) / 'control/hybrid_v028_20261014_001/stage_results').glob('attacks_*.json'), key=lambda p: p.stat().st_mtime)[-6:]
emit('FS_STAGES', [dict(name=p.name, value=json.loads(p.read_text())) for p in stage])
FS
