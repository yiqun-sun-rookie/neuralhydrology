#!/bin/bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - <<'DIAG'
"""Read-only diagnosis of failed job 242753: logs, accounting, sbatch script, saved records. No mutation."""
import json, subprocess, hashlib
from pathlib import Path
r = Path('/data1/home/sunyiq/hydrol85935_temporal_attempts/hpc_v009_001/hydrol85935_temporal_persistence_20261011_001')
t = r / 'attempts/infeasible_recovery_v002_20261015_001'
def emit(k, v): print(k + ' ' + json.dumps(v), flush=True)
def run(cmd):
    x = subprocess.run(cmd, capture_output=True, text=True, timeout=45)
    return dict(returncode=x.returncode, stdout=x.stdout, stderr=x.stderr)
emit('DIAG_ACCOUNTING', run(['sacct', '-j', '242753,242754', '-P', '-o', 'JobID,State,ExitCode,DerivedExitCode,Elapsed,Start,End,NodeList,Reason,MaxRSS,ReqMem']))
emit('DIAG_SCONTROL', run(['scontrol', 'show', 'job', '-o', '242753']))
logs = sorted((t / 'logs').glob('*242753*'))
emit('DIAG_LOG_FILES', [dict(path=str(p), bytes=p.stat().st_size, mtime=p.stat().st_mtime) for p in logs])
for p in logs:
    data = p.read_bytes()
    emit('DIAG_LOG', dict(path=str(p), bytes=len(data), head=data[:2500].decode('utf8', 'replace'), tail=data[-9000:].decode('utf8', 'replace')))
s = t / 'submissions/s100_missing.sbatch'
if s.exists(): emit('DIAG_SBATCH', dict(path=str(s), sha256=hashlib.sha256(s.read_bytes()).hexdigest(), text=s.read_text()))
reg = t / 'registered.json'
emit('DIAG_REGISTERED_SHA', hashlib.sha256(reg.read_bytes()).hexdigest())
for d in sorted((t / 'records').glob('single_temperature_s100/*'))[-12:]:
    emit('DIAG_S100_RECORD', dict(path=str(d), files=sorted(x.name for x in d.iterdir()), mtime=d.stat().st_mtime))
emit('DIAG_UNCOMPUTABLE', [dict(path=str(p), sha256=hashlib.sha256(p.read_bytes()).hexdigest(), text=p.read_text()[:2500]) for p in sorted(t.glob('records/**/*uncomputable*'))[:12]])
emit('DIAG_FILES_NEWEST', [dict(path=str(p), bytes=p.stat().st_size, mtime=p.stat().st_mtime) for p in sorted((p for p in t.rglob('*') if p.is_file()), key=lambda q: q.stat().st_mtime)[-15:]])
DIAG
