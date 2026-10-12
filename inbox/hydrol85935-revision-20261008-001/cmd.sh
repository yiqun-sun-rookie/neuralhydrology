#!/usr/bin/env bash
set -eo pipefail
ROOT=/data1/home/sunyiq/hydrol85935_revision_20261008_001
test "$(readlink -f "$ROOT")" = "$ROOT"
test "$(cat "$ROOT/OWNER")" = hydrol85935_revision_20261008_001
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - <<'PY'
import datetime
import json
import re
from pathlib import Path
import subprocess

root = Path('/data1/home/sunyiq/hydrol85935_revision_20261008_001')
execution = root / 'execution/v004'

def output(label, value):
    print(label + ' ' + json.dumps(value, ensure_ascii=False), flush=True)

def safe(path):
    path.resolve().relative_to(root)
    return path

def metadata(path):
    path = safe(path)
    if not path.exists():
        return {'path': str(path.relative_to(root)), 'exists': False}
    s = path.stat()
    return {'path': str(path.relative_to(root)), 'exists': True,
            'bytes': s.st_size, 'mtime_ns': s.st_mtime_ns}

def small_file(relative):
    p = root / relative
    result = metadata(p)
    if result['exists']:
        if result['bytes'] > 65536:
            raise ValueError('Unexpectedly large status file: ' + relative)
        result['text'] = p.read_text()
    output('FILE', result)

def tail(path, limit=5000):
    info = metadata(path)
    if info['exists']:
        with path.open('rb') as stream:
            stream.seek(max(0, info['bytes'] - limit))
            info['tail'] = stream.read().decode(errors='replace')
    output('LOG', info)

output('OBSERVATION', {'time': datetime.datetime.now().astimezone().isoformat(),
                       'scope': 'read-only scheduler, task status, logs and output metadata; no science execution'})
for relative in [
    'control/continuation_v004/status.json', 'control/full_v004/jobs.json',
    'control/continuation_v004/coordinator_pid',
    'runtime_torch271cu118/DOWNLOAD_COMPLETE.json',
    'runtime_torch271cu118/INSTALL_COMPLETE.json',
    'control/resource_pilot_v004.json',
    'execution/v004/control/train_failure.json',
    'execution/v004/control/main_failure.json',
    'execution/v004/control/validation.json',
]:
    small_file(relative)
jobs = json.loads((root / 'control/full_v004/jobs.json').read_text())
if jobs != {'train': 240076, 'attacks': 240077, 'report': 240078}:
    raise ValueError('Unrecognized job registry; stop rather than infer ownership')
for label, command in [
    ('SQUEUE', ['squeue', '-j', ','.join(str(j) for j in jobs.values()), '-o',
                '%.24i %.10T %.12M %.6C %.16b %.30R']),
    ('SACCT', ['sacct', '-X', '-j', '240074,240075,' + ','.join(str(j) for j in jobs.values()),
               '-n', '-P', '-o', 'JobID,State,ExitCode,Elapsed,Start,End,NodeList']),
    ('TRAIN_DETAIL', ['scontrol', '-o', 'show', 'job', str(jobs['train'])]),
]:
    result = subprocess.run(command, capture_output=True, text=True, timeout=45)
    output(label, {'returncode': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr})
pid = (root / 'control/continuation_v004/coordinator_pid').read_text().strip()
if not pid.isdigit():
    raise ValueError('Invalid coordinator PID')
result = subprocess.run(['ps', '-p', pid, '-o', 'pid,etimes,args'], capture_output=True, text=True, timeout=15)
output('COORDINATOR', {'returncode': result.returncode, 'stdout': result.stdout,
                       'absence_expected_after_formal_handoff': True})
for seed in (100, 200, 300):
    directory = execution / 'training' / ('s' + str(seed))
    small_file(str((directory / 'complete.json').relative_to(root)))
    files = sorted(directory.glob('runs/*/model_epoch*.pt'))
    output('TRAIN_CHECKPOINTS', {'seed': seed, 'count': len(files),
                                'latest': [metadata(p) for p in files[-3:]]})
    for p in sorted(directory.glob('runs/*/*.log'))[-3:]:
        tail(p)
for pattern in ['train-240076_*.out', 'train-240076_*.err',
                'attacks-240077_*.out', 'attacks-240077_*.err',
                'report-240078*.out', 'report-240078*.err']:
    paths = sorted((root / 'logs').glob(pattern), key=lambda p: p.stat().st_mtime_ns)
    output('LOG_INVENTORY', {'pattern': pattern, 'count': len(paths)})
    for p in paths[-4:]:
        tail(p)
for name, pattern in [('attack_complete_markers', 'records/attacks/*/*/complete.json'),
                      ('clean_complete_markers', 'records/clean/*/*/complete.json'),
                      ('chunk_summaries', 'control/chunk_*.json')]:
    paths = list(execution.glob(pattern))
    output('OUTPUT_METADATA', {'kind': name, 'count': len(paths),
                               'latest': [metadata(p) for p in sorted(paths, key=lambda p: p.stat().st_mtime_ns)[-3:]],
                               'complete_coverage_audit': False})
tail(execution / 'records/ledger.jsonl', 4000)

for label, command in [
    ('QUEUE_START_ESTIMATE', ['squeue', '--start', '-j', '240076', '-o',
                             '%.24i %.10T %.19S %.30R']),
    ('JOB_PRIORITY', ['sprio', '-j', '240076', '-l']),
    ('USER_FAIR_SHARE', ['sshare', '-U', '-P']),
    ('PARTITION_LOAD', ['sinfo', '-p', 'hgpu2p', '-N', '-O',
                        'nodelist,statelong,gres,gresused']),
]:
    result = subprocess.run(command, capture_output=True, text=True, timeout=45)
    output(label, {'returncode': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr})

result = subprocess.run(['sinfo', '-h', '-o', '%P|%a|%l|%D|%t|%G|%N'], capture_output=True, text=True, timeout=45)
output('ALL_PARTITIONS', {'returncode': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr})
if result.returncode:
    raise RuntimeError('Cannot enumerate all partitions')
result = subprocess.run(['sinfo', '-N', '-h', '-O', 'partitionname:20,nodelist:20,statelong:20,gres:20,gresused:30,cpusstate:22'], capture_output=True, text=True, timeout=45)
if result.returncode:
    output('ALL_GPU_NODES', {'returncode': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr})
    raise RuntimeError('Cannot enumerate allocated GPU resources')
def has_configured_accelerator(line):
    fields = line.split()
    if len(fields) < 6:
        raise ValueError('Malformed node inventory row')
    # Capacity is the fourth column; allocated gpu:0 on CPU nodes is not capacity.
    return any(re.fullmatch(r'(?:gpu|dcu):(?:[^:,]+:)?[1-9][0-9]*(?:[(].*[)])?', item)
               for item in fields[3].split(','))
gpu_lines = [line for line in result.stdout.splitlines() if has_configured_accelerator(line)]
output('ALL_GPU_NODES', {'returncode': 0, 'stdout': '\n'.join(gpu_lines) + '\n', 'stderr': result.stderr, 'all_node_rows': len(result.stdout.splitlines()), 'gpu_node_rows': len(gpu_lines)})
PY

/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - <<'PY'
import hashlib,json,subprocess
from pathlib import Path
root=Path('/data1/home/sunyiq/hydrol85935_revision_20261008_001')
d=root/'control/migration_probe_20261012_002'
assert d.resolve().parent==root/'control'
def show(label,value):print(label+' '+json.dumps(value),flush=True)
for name in ['jobs.json','submission.jsonl','ngu201_report.json','ngu002_report.json']:
 p=d/name
 value=dict(path=str(p.relative_to(root)),exists=p.exists())
 if p.exists():
  data=p.read_bytes();assert len(data)<65536
  value.update(bytes=len(data),sha256=hashlib.sha256(data).hexdigest(),text=data.decode())
 show('COMPATIBILITY_FILE',value)
p=d/'jobs.json'
if p.exists():
 registry=json.loads(p.read_text())
 assert registry['formal_jobs']==dict(train=240076,attacks=240077,report=240078)
 assert set(registry['probes'])=={'ngu201','ngu002'}
 assert all(isinstance(j,int) and j>0 for j in registry['probes'].values())
 jobs=','.join(str(j) for j in registry['probes'].values())
 for label,command in [('COMPATIBILITY_SQUEUE',['squeue','-j',jobs,'-o','%.24i %.10T %.12M %.6C %.16b %.30R']),('COMPATIBILITY_SACCT',['sacct','-X','-j',jobs,'-n','-P','-o','JobID,State,ExitCode,Elapsed,Start,End,NodeList'])]:
  r=subprocess.run(command,text=True,capture_output=True,timeout=45)
  show(label,dict(returncode=r.returncode,stdout=r.stdout,stderr=r.stderr))
  if r.returncode:raise RuntimeError('Cannot verify compatibility scheduler state')
 for node,job in registry['probes'].items():
  for suffix in ['out','err']:
   p=d/(node+'-'+str(job)+'.'+suffix)
   value=dict(path=str(p.relative_to(root)),exists=p.exists())
   if p.exists():
    with p.open('rb') as f:f.seek(max(0,p.stat().st_size-12000));tail=f.read()
    value.update(bytes=p.stat().st_size,tail=tail.decode(errors='replace'))
   show('COMPATIBILITY_LOG',value)
PY

/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - <<'PY'
import hashlib,json,subprocess
from pathlib import Path
root=Path('/data1/home/sunyiq/hydrol85935_revision_20261008_001')
d=root/'control/migration_gate_v005_20261012_002'
assert d.resolve().parent==root/'control'
def show(label,value):print(label+' '+json.dumps(value),flush=True)
for p in [d/'jobs.json',d/'runtime.json',d/'original_cases.json',d/'failure.json',d/'resource_layout.json',root/'control/migration_gate_v005.json',root/'control/resource_pilot_v005.json',root/'control/preflight_v005_job_id']:
 value=dict(path=str(p.relative_to(root)),exists=p.exists())
 if p.exists():
  data=p.read_bytes();assert len(data)<65536
  value.update(bytes=len(data),sha256=hashlib.sha256(data).hexdigest(),text=data.decode())
 show('MIGRATION_GATE_FILE',value)
registry_path=d/'jobs.json'
if registry_path.exists():
 registry=json.loads(registry_path.read_text());assert registry['formal_jobs']==dict(train=240076,attacks=240077,report=240078)
 assert set(registry['probes'])=={'ngu002'}
 job=registry['probes']['ngu002'];assert isinstance(job,int) and job>0
 for label,command in [('MIGRATION_GATE_SQUEUE',['squeue','-j',str(job),'-o','%.24i %.10T %.12M %.6C %.16b %.30R']),('MIGRATION_GATE_SACCT',['sacct','-X','-j',str(job),'-n','-P','-o','JobID,State,ExitCode,Elapsed,Start,End,NodeList'])]:
  result=subprocess.run(command,text=True,capture_output=True,timeout=45)
  show(label,dict(returncode=result.returncode,stdout=result.stdout,stderr=result.stderr))
  if result.returncode:raise RuntimeError('Cannot verify full migration gate state')
 for p in [d/'progress.jsonl',d/'submission.jsonl',d/'code_tests.stdout',d/'code_tests.stderr',d/('ngu002-'+str(job)+'.out'),d/('ngu002-'+str(job)+'.err')]:
  value=dict(path=str(p.relative_to(root)),exists=p.exists())
  if p.exists():
   with p.open('rb') as f:f.seek(max(0,p.stat().st_size-12000));tail=f.read()
   value.update(bytes=p.stat().st_size,tail=tail.decode(errors='replace'))
  show('MIGRATION_GATE_LOG',value)
PY

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
owner_path = root / 'control/local_gpu_partial_20261012_001/ownership.json'
if not owner_path.exists():
    raise RuntimeError('Local ownership record missing; do not release or submit compute')
owner = json.loads(owner_path.read_text())
if owner['owner'] != 'local' or owner['jobs'] != dict(train=240076, attacks=240077, report=240078):
    raise RuntimeError('Local ownership identity changed')
output('REMOTE_LOCAL_OWNER', owner)
for label, job in owner['jobs'].items():
    query('LOCAL_HELD_JOB_' + label, ['scontrol', 'show', 'job', '-o', str(job)])
PY
