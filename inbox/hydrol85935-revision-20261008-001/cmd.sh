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

def output(label, value):
    print(label + ' ' + json.dumps(value, ensure_ascii=False), flush=True)

def query(label, command):
    result = subprocess.run(command, capture_output=True, text=True, timeout=45)
    output(label, dict(returncode=result.returncode, stdout=result.stdout, stderr=result.stderr))
    if result.returncode:
        raise RuntimeError('Cannot verify ' + label)
    return result.stdout

output('OBSERVATION', dict(time=datetime.datetime.now().astimezone().isoformat(),
       scope='read-only GPU inventory and registered scheduler state; not a full experiment audit'))
jobs = json.loads((root / 'control/full_v004/jobs.json').read_text())
if jobs != dict(train=240076, attacks=240077, report=240078):
    raise ValueError('Job registry changed; review version and ownership before using a new probe')
probe_path = root / 'control/migration_probe_20261012_002/jobs.json'
if probe_path.exists():
    probe_registry = json.loads(probe_path.read_text())
    if probe_registry['formal_jobs'] != jobs or probe_registry['probes'] != dict(ngu201=241239, ngu002=241240):
        raise ValueError('Compatibility job registry changed; review identity before querying')
    jobs = dict(jobs, compatibility_ngu201=241239, compatibility_ngu002=241240)
output('REGISTERED_JOBS', jobs)
query('SQUEUE', ['squeue', '-j', ','.join(str(j) for j in jobs.values()), '-o',
                 '%.24i %.10T %.12M %.6C %.16b %.30R'])
query('SACCT', ['sacct', '-X', '-j', ','.join(str(j) for j in jobs.values()),
               '-n', '-P', '-o', 'JobID,State,ExitCode,Elapsed,Start,End,NodeList'])
query('ALL_PARTITIONS', ['sinfo', '-h', '-o', '%P|%a|%l|%D|%t|%G|%N'])
result = subprocess.run(['sinfo', '-N', '-h', '-O',
    'partitionname:20,nodelist:20,statelong:20,gres:20,gresused:30,cpusstate:22'],
    capture_output=True, text=True, timeout=45)
if result.returncode:
    output('ALL_GPU_NODES', dict(returncode=result.returncode, stdout=result.stdout, stderr=result.stderr))
    raise RuntimeError('Cannot enumerate GPU resources')

def has_accelerator(line):
    fields = line.split()
    if len(fields) < 6:
        raise ValueError('Malformed node inventory row')
    return any(re.fullmatch(r'(?:gpu|dcu):(?:[^:,]+:)?[1-9][0-9]*(?:[(].*[)])?', item)
               for item in fields[3].split(','))

rows = [line for line in result.stdout.splitlines() if has_accelerator(line)]
output('ALL_GPU_NODES', dict(returncode=0, stdout='\n'.join(rows)+'\n', stderr=result.stderr,
       all_node_rows=len(result.stdout.splitlines()), gpu_node_rows=len(rows)))
owner_path = root / 'control/local_cpu_partial_20261012_001/ownership.json'
if not owner_path.exists():
    raise RuntimeError('Local ownership record missing; do not release or submit compute')
owner = json.loads(owner_path.read_text())
if owner['owner'] != 'local' or owner['jobs'] != dict(train=240076, attacks=240077, report=240078):
    raise RuntimeError('Local ownership identity changed')
output('REMOTE_LOCAL_OWNER', owner)
for label, job in owner['jobs'].items():
    query('LOCAL_HELD_JOB_' + label, ['scontrol', 'show', 'job', '-o', str(job)])
PY

/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - <<'PY'
import json,subprocess,datetime
from pathlib import Path
root=Path('/data1/home/sunyiq/hydrol85935_revision_20261008_001')
old=json.loads((root/'control/local_cpu_partial_20261012_001/ownership.json').read_text())
for label,job in old['jobs'].items():
 r=subprocess.run(['scontrol','show','job','-o',str(job)],capture_output=True,text=True,check=True,timeout=45)
 fields=dict(part.split('=',1) for part in r.stdout.split() if '=' in part)
 expected={'JobState':'PENDING','Reason':'JobHeldUser','Priority':'0','RunTime':'00:00:00','NodeList':'(null)','Command':str(root/'control/full_v004'/f'{label}.sbatch'),'WorkDir':str(root/'control/continuation_v004')}
 assert all(fields.get(k)==v for k,v in expected.items()),(label,fields)
folder=root/'control/local_gpu_partial_20261012_001';folder.mkdir(exist_ok=False)
owner=dict(old,version='local_gpu_v008_20261012_001',local_root='G:/hydrol85935_revision_20261008_001/local_gpu_v008',assignment_sha256='c882884441a44ce5e3a8097c99eeab3a832ea0e010556d5ecd1cce97ac13345e',device='cuda:0',cpu_limit=2,total_local_cpu_limit=4,gpu_budget_gib=3,cpu_assignment_record='control/local_cpu_partial_20261012_001/ownership.json',nonoverlap='CPU indices0:25, GPU25:50, original_s100 all11; gate GPU pilot excluded from formal union',utc=datetime.datetime.now(datetime.timezone.utc).isoformat())
(folder/'ownership.json').write_text(json.dumps(owner,indent=2));print('NEW_LOCAL_GPU_OWNER '+json.dumps(owner),flush=True)
PY
