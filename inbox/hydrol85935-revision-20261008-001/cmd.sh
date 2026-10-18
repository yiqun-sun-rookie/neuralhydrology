#!/bin/bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - <<'PP'
"""Read-only: scheduler and record-count view of the paper-line pre-peak array 244280. No mutation."""
import json, subprocess, datetime
from pathlib import Path
def emit(k, v): print(k + ' ' + json.dumps(v, ensure_ascii=True), flush=True)
def run(a):
    r = subprocess.run(a, capture_output=True, text=True, timeout=45); return dict(returncode=r.returncode, stdout=r.stdout[:6000], stderr=r.stderr[:500])
emit('PP_TIME', dict(utc=datetime.datetime.now(datetime.timezone.utc).isoformat()))
emit('PP_SACCT', run(['sacct', '-X', '-j', '244280', '-n', '-P', '-o', 'JobID,State,ExitCode,Elapsed,Start,End,NodeList']))
emit('PP_SQUEUE', run(['squeue', '-h', '-r', '-j', '244280', '-o', '%i|%T|%r|%M|%N']))
root = Path('/data1/home/sunyiq/hydrol85935_prepeak_small_bounds_20261017_001')
if root.exists():
    recs = list(root.rglob('*.json'))
    emit('PP_FILES', dict(root=str(root), json_files=len(recs), newest=[str(p.relative_to(root)) for p in sorted(recs, key=lambda p: p.stat().st_mtime)[-3:]]))
PP
