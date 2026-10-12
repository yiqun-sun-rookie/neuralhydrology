#!/usr/bin/env bash
set -eo pipefail
ROOT=/data1/home/sunyiq/hydrol85935_revision_20261008_001
test "$(readlink -f "$ROOT")" = "$ROOT"
test "$(cat "$ROOT/OWNER")" = hydrol85935_revision_20261008_001
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - <<'PY'
import datetime
import json
from pathlib import Path
import subprocess

root = Path('/data1/home/sunyiq/hydrol85935_revision_20261008_001')
def emit(label, obj):
    print(label + ' ' + json.dumps(obj), flush=True)
def run(label, args):
    r = subprocess.run(args, capture_output=True, text=True, timeout=45)
    emit(label, dict(returncode=r.returncode, stdout=r.stdout, stderr=r.stderr))
    if r.returncode:
        raise RuntimeError(label + ' failed')
    return r.stdout

emit('OBSERVATION', dict(time=datetime.datetime.now().astimezone().isoformat(), scope='Read-only GPU partition inventory and protected job snapshot'))
jobs = json.loads((root / 'control/full_v004/jobs.json').read_text())
assert jobs == dict(train=240076, attacks=240077, report=240078)
emit('REGISTERED_JOBS', jobs)
run('GPU_PARTITIONS', ['sinfo', '-p', 'hgpu2p,hgpu2,hgpu4,hgpu8', '-N', '-O', 'partitionname:12,nodelist:16,statelong:16,gres:18,gresused:30,cpusstate:24'])
names = run('GPU_NODE_NAMES', ['sinfo', '-h', '-N', '-p', 'hgpu2p,hgpu2,hgpu4,hgpu8', '-o', '%N'])
for node in sorted(set(names.split())):
    run('GPU_NODE_DETAIL', ['scontrol', '-o', 'show', 'node', node])
for partition in ('hgpu2p', 'hgpu2', 'hgpu4', 'hgpu8'):
    run('PARTITION_DETAIL', ['scontrol', '-o', 'show', 'partition', partition])
run('USER_JOBS_PROTECTED_SNAPSHOT', ['squeue', '-u', 'sunyiq', '-o', '%.24i %.32j %.10P %.12T %.8C %.16b %.20N %.30R'])
for job in jobs.values():
    run('OWN_FORMAL_DETAIL', ['scontrol', '-o', 'show', 'job', str(job)])
run('OWN_FORMAL_ACCOUNTING', ['sacct', '-X', '-j', '240076,240077,240078', '-n', '-P', '-o', 'JobID,State,ExitCode,Elapsed,Start,End,NodeList'])
run('OWN_START_ESTIMATE', ['squeue', '--start', '-j', '240076', '-o', '%.24i %.10T %.19S %.30R'])
for name in ('DOWNLOAD_COMPLETE.json', 'INSTALL_COMPLETE.json'):
    p = root / 'runtime_torch271cu118' / name
    emit('RUNTIME_MARKER', dict(path=str(p), exists=p.exists(), text=p.read_text() if p.exists() else None))
PY
