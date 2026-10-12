#!/usr/bin/env bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
ROOT=/data1/home/sunyiq/hydrol85935_revision_20261008_001
test "$(readlink -f "$ROOT")" = "$ROOT"
test "$(cat "$ROOT/OWNER")" = hydrol85935_revision_20261008_001
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - <<'PY'
import datetime
import json
import re
import subprocess
from pathlib import Path

root = Path('/data1/home/sunyiq/hydrol85935_revision_20261008_001')
jobs = dict(train=240076, attacks=240077, report=240078)
assert json.loads((root / 'control/full_v004/jobs.json').read_text()) == jobs
dest = root / 'control/local_takeover_20261012_002'
dest.mkdir(exist_ok=False)

def query(args):
    r = subprocess.run(args, capture_output=True, text=True, timeout=45)
    row = dict(utc=datetime.datetime.now(datetime.timezone.utc).isoformat(), command=args,
               returncode=r.returncode, stdout=r.stdout, stderr=r.stderr)
    with (dest / 'operations.jsonl').open('a') as f:
        f.write(json.dumps(row) + '\n')
    print('OPERATION ' + json.dumps(row), flush=True)
    if r.returncode:
        raise RuntimeError('Scheduler action could not be confirmed')
    return r.stdout

def verify(stage, held=False):
    evidence = {}
    queue = query(['squeue', '-h', '-j', ','.join(map(str, jobs.values())), '-o', '%i|%T|%R'])
    if not queue.strip() or any(line.split('|')[1].strip() != 'PENDING' for line in queue.splitlines()):
        raise RuntimeError('A registered task is no longer exclusively pending; local takeover denied')
    for label, job in jobs.items():
        raw = query(['scontrol', 'show', 'job', '-o', str(job)])
        lines = raw.splitlines()
        if not lines:
            raise ValueError('Missing scheduler job identity')
        for line in lines:
            fields = dict(re.findall(r'(?:^|\s)([A-Za-z_]+)=([^\s]+)', line))
            assert fields['Command'] == str(root / 'control/full_v004' / (label + '.sbatch'))
            assert fields['WorkDir'] == str(root / 'control/continuation_v004')
            assert fields['JobState'] == 'PENDING'
            assert fields['NodeList'] == '(null)' and fields['RunTime'] == '00:00:00'
            assert fields['JobId'].split('_')[0] == str(job)
            if held:
                assert fields['Priority'] == '0' and fields['Reason'] == 'JobHeldUser'
        evidence[label] = raw
    (dest / (stage + '.json')).write_text(json.dumps(evidence, indent=2))
    return evidence

before = verify('before')
for label, job in jobs.items():
    query(['scontrol', 'hold', str(job)])
after = verify('after', held=True)
owner = dict(status='HPC_HELD_LOCAL_OWNERSHIP_CONFIRMED', owner='local',
             identity='hydrol85935_revision_20261008_001', version='local_v006_20261012_001',
             jobs=jobs, local_root=r'G:\hydrol85935_revision_20261008_001\local_v006',
             utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
             path_identity_verified=True, all_formal_jobs_pending_and_user_held=True,
             other_experiments_modified=False, scientific_jobs_started=0,
             authorization='2026-10-12 user: start locally if feasible; protect existing work; avoid HPC duplication')
with (dest / 'ownership.json').open('x') as f:
    json.dump(owner, f, indent=2)
print('LOCAL_OWNERSHIP ' + json.dumps(owner), flush=True)
PY
