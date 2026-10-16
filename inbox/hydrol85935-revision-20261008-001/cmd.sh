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
folder = root / 'control/hybrid_v026_20261014_001'
scheduler_folder = root / 'control/hybrid_v009_20261012_001'
import hashlib
owner = json.loads((folder/'ownership.json').read_text())
assignment_raw=(folder/'assignment.json').read_bytes()
if owner['owner']!='split_local_hpc' or hashlib.sha256(assignment_raw).hexdigest()!=owner['assignment_sha256']:
    raise RuntimeError('Hybrid assignment or owner identity changed')
bridges=json.loads((folder/'deployment_transaction.json').read_text())['entrypoints']
for entry in bridges:
    if hashlib.sha256(Path(entry['path']).read_bytes()).hexdigest()!=entry['new_sha256']:
        raise RuntimeError('Active orchestration bridge changed: '+entry['path'])
output('ACTIVE_ORCHESTRATION',bridges)
output('HYBRID_OWNER',owner)
current=json.loads((folder/'jobs.json').read_text())
output('HYBRID_JOBS',current)
for label,job in dict(train=240076,attacks=240077,report=240078).items():
    result=query('OLD_HELD_JOB_'+label,['scontrol','show','job','-o',str(job)])
    for token in ['JobState=PENDING ','Reason=JobHeldUser ','Priority=0 ',f'Command={root}/control/full_v004/{label}.sbatch ',f'WorkDir={root}/control/continuation_v004 ']:
        if token not in result:raise RuntimeError('Old full-job hold or path identity changed: '+label)
if current:
    ids=','.join(str(j) for j in current.values())
    query('HYBRID_SQUEUE',['squeue','-j',ids,'-o','%.24i %.10T %.12M %.6C %.16b %.40R'])
    query('HYBRID_SACCT',['sacct','-X','-j',ids,'-n','-P','-o','JobID,State,ExitCode,Elapsed,Start,End,NodeList'])
    for label,job in current.items():
        r=subprocess.run(['scontrol','show','job','-o',str(job)],capture_output=True,text=True,timeout=45)
        output('HYBRID_JOB_'+label,dict(returncode=r.returncode,stdout=r.stdout,stderr=r.stderr))
        if r.returncode==0:
            for token in [f'Command={scheduler_folder}/{label}.sbatch ',f'WorkDir={scheduler_folder} ','CPUs/Task=4 ','TresPerNode=gpu:1']:
                if token not in r.stdout:raise RuntimeError('New job identity/resource mismatch: '+label)
            if label in ('train','attacks') and 'ArrayTaskThrottle=1 ' not in r.stdout:raise RuntimeError('Array concurrency changed')
PY

/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - <<'PY'
import json,subprocess,hashlib
from pathlib import Path
root=Path('/data1/home/sunyiq/hydrol85935_revision_20261008_001')
f=root/'control/workflow_v010_20261012_001'
t=Path('/data1/home/sunyiq/hydrol85935_temporal_attempts/hpc_v009_001/hydrol85935_temporal_persistence_20261011_001')
def emit(k,v):print(k+' '+json.dumps(v),flush=True)
registry=f/'registration.json'
if not registry.exists():
 emit('WORKFLOW_V010',dict(status='REGISTRATION_NOT_CONFIRMED',folder=str(f)))
else:
 reg=json.loads(registry.read_text());emit('WORKFLOW_V010',reg)
 jobs=[('endpoint_export',reg['export_job'],f/'export.sbatch')]
 for p in sorted((t/'control/submissions').glob('*.json')):
  if '.attempt.' in p.name:continue
  data=json.loads(p.read_text())
  if 'job_id' not in data:continue
  emit('TEMPORAL_SUBMISSION',data)
  jobs.append(('temporal_'+data['stage'],data['job_id'],p.with_suffix('.sbatch')))
 for name,jid,script in jobs:
  r=subprocess.run(['scontrol','show','job','-o',str(jid)],capture_output=True,text=True,timeout=45)
  emit('WORKFLOW_JOB',dict(name=name,job_id=jid,returncode=r.returncode,stdout=r.stdout,stderr=r.stderr))
  if r.returncode==0:
   for token in [f'Command={script} ','CPUs/Task=4 ','TresPerNode=gpu:1'] + (['WorkDir=/data1/home/sunyiq/hpc_mailbox '] if jid in (241344,241345) else []):
    if token not in r.stdout:raise RuntimeError('Registered workflow identity changed: '+name+' '+token)
   if name.startswith('temporal_main') and 'ArrayTaskThrottle=1 ' not in r.stdout:raise RuntimeError('Temporal concurrency changed')
  a=subprocess.run(['sacct','-X','-j',str(jid),'-n','-P','-o','JobID,State,ExitCode,Elapsed,Start,End,NodeList'],capture_output=True,text=True,timeout=45)
  emit('WORKFLOW_ACCOUNTING',dict(name=name,job_id=jid,returncode=a.returncode,stdout=a.stdout,stderr=a.stderr))
 for p in [root/'control/hybrid_v026_20261014_001/hpc_packet_001/index.json',t/'control/parent_binding_v010.json',t/'control/new_models_verified.json',t/'control/resource_pilot.json',t/'reports/coverage_and_summary.json']:
  if p.is_file():emit('WORKFLOW_RESULT',dict(path=str(p),sha256=hashlib.sha256(p.read_bytes()).hexdigest(),value=json.loads(p.read_text())))
PY
