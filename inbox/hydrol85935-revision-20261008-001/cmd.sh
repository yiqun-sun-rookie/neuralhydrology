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
folder = root / 'control/hybrid_v020_20261014_001'
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
import json,subprocess
from pathlib import Path
root=Path('/data1/home/sunyiq/hydrol85935_revision_20261008_001')
folder=root/'control/hybrid_v020_20261014_001';scheduler_folder=root/'control/hybrid_v009_20261012_001';execution=root/'execution/hpc_v009'
def emit(label,value):print(label+' '+json.dumps(value),flush=True)
for name in ['submission_attempt.json','jobs.json','ownership.json']:
    path=folder/name;emit('HYBRID_CONTROL',dict(path=str(path),value=json.loads(path.read_text()) if path.exists() else None))
for seed in (100,200,300):
    files=list((execution/f'training/s{seed}').rglob('model_epoch*.pt'))
    emit('HYBRID_TRAINING',dict(seed=seed,checkpoint_count=len(files),complete=(execution/f'training/s{seed}/complete.json').exists(),latest=[dict(path=str(p),bytes=p.stat().st_size,mtime=p.stat().st_mtime) for p in sorted(files,key=lambda q:q.stat().st_mtime)[-3:]]))
for label,pattern in [('attacks','records/attacks/*/*/complete.json'),('clean','records/clean/*/*/complete.json')]:
    files=list(execution.glob(pattern));emit('HYBRID_OUTPUT_METADATA',dict(kind=label,marker_count=len(files),not_full_slot_validation=True))
for p in sorted((folder/'stage_results').glob('*.json'),key=lambda q:q.stat().st_mtime)[-8:]:
    value=json.loads(p.read_text());emit('HYBRID_STAGE',dict(path=str(p),bytes=p.stat().st_size,status=value.get('status'),stage=value.get('stage'),index=value.get('index'),exit_code=value.get('exit_code'),counts=value.get('counts'),failures_count=len(value.get('failures',[])),traceback=value.get('traceback'),global_science_complete=False))
for p in sorted((scheduler_folder/'logs').glob('*'),key=lambda q:q.stat().st_mtime)[-6:]:
    with p.open('rb') as f:
        f.seek(max(0,p.stat().st_size-3500));tail=f.read().decode('utf8',errors='replace')
    emit('HYBRID_LOG',dict(path=str(p),bytes=p.stat().st_size,mtime=p.stat().st_mtime,tail=tail))
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
 for p in [root/'control/hybrid_v020_20261014_001/hpc_packet_001/index.json',t/'control/parent_binding_v010.json',t/'control/new_models_verified.json',t/'control/resource_pilot.json',t/'reports/coverage_and_summary.json']:
  if p.is_file():emit('WORKFLOW_RESULT',dict(path=str(p),sha256=hashlib.sha256(p.read_bytes()).hexdigest(),value=json.loads(p.read_text())))
PY

/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - <<'DETAIL'
"""Finite login-node metadata audit; no scientific computation or mutations."""
import collections
import hashlib
import json
import subprocess
from pathlib import Path

ROOT = Path('/data1/home/sunyiq/hydrol85935_revision_20261008_001')
CONTROL = ROOT / 'control/hybrid_v020_20261014_001'
EXECUTION = ROOT / 'execution/hpc_v009'
SCHED = ROOT / 'control/hybrid_v009_20261012_001'

def emit(k, v):
    print(k + ' ' + json.dumps(v), flush=True)

def query(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=45)
    assert r.returncode == 0, (cmd, r.stderr)
    return r.stdout

def main():
    assignment = json.loads((CONTROL / 'assignment.json').read_text())
    ledger = EXECUTION / 'records/ledger.jsonl'
    rows = [json.loads(x) for x in ledger.read_text().splitlines() if x.strip()] if ledger.exists() else []
    failures = [r for r in rows if r.get('status') in ('failed', 'uncomputable')]
    emit('ALL_FAILURE_HISTORY', dict(rows=failures, count=len(failures), ledger_sha256=hashlib.sha256(ledger.read_bytes()).hexdigest()))
    controls = list((ROOT / 'control').glob('hybrid_v*'))
    candidates = []
    for task in assignment['hpc_tasks']:
        if task['model'] != 'original_s100' or not task['basins']:
            continue
        i = task['index']
        occupied = [(r.get('combination_id'), r.get('basin_id'), r.get('status')) for r in rows
                    if str(r.get('basin_id')) in task['basins'] and
                    (r.get('combination_id') in task['combinations'] or r.get('model_id') == task['model'])]
        outputs = [str(p) for b in task['basins']
                   for p in [EXECUTION/'records/clean'/task['model']/b] +
                   [EXECUTION/'records/attacks'/c/b for c in task['combinations']] if p.exists()]
        stages = [str(p) for c in controls for p in (c/'stage_results').glob('attacks_'+str(i)+'_*.json')]
        logs = [str(p) for p in (SCHED/'logs').glob('attacks-241336_'+str(i)+'.*')]
        candidates.append(dict(index=i, start=task['basin_start'], count=task['basin_count'],
                               basins=task['basins'], output_paths=outputs, ledger_occupancy=occupied,
                               stage_history=stages, scheduler_logs=logs,
                               no_occupancy=not any((outputs, occupied, stages, logs))))
    emit('CANDIDATE_OCCUPANCY', candidates)
    emit('RUNNING_SCHEDULER', query(['scontrol','show','job','-o','241336']))
    emit('COMPLETE_ARRAY_HISTORY', query(['sacct','-X','-j','241336','-n','-P','-o','JobID,State,ExitCode,Elapsed,Start,End,NodeList']))
    emit('TRAIN_STAGE_PROOFS', [dict(path=str(p),sha256=hashlib.sha256(p.read_bytes()).hexdigest(),value=json.loads(p.read_text()))
                               for c in controls for p in (c/'stage_results').glob('train_*.json')])
    emit('ORCHESTRATION_SOURCE_PROOF', dict(worker_sha256=hashlib.sha256((CONTROL/'worker.py').read_bytes()).hexdigest(),
                                           assignment_sha256=hashlib.sha256((CONTROL/'assignment.json').read_bytes()).hexdigest()))

if __name__ == '__main__':
    main()

DETAIL

/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - <<'RECOVERY'
import json,hashlib,subprocess
from pathlib import Path
r=Path('/data1/home/sunyiq/hydrol85935_temporal_attempts/hpc_v009_001/hydrol85935_temporal_persistence_20261011_001/attempts/infeasible_recovery_v002_20261015_001')
def emit(k,v):print(k+' '+json.dumps(v),flush=True)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
reg=json.loads((r/'registered.json').read_text())
emit('SUPPLEMENTARY_RECOVERY_REGISTRATION',dict(path=str(r/'registered.json'),sha256=sha(r/'registered.json'),value=reg))
for j in reg['jobs']:
 script=Path(j['script']);assert sha(script)==j['script_sha256']
 result=subprocess.run(['scontrol','show','job','-o',str(j['job_id'])],capture_output=True,text=True,timeout=45)
 hist=subprocess.run(['sacct','-X','-j',str(j['job_id']),'-n','-P','-o','JobID,State,ExitCode,Elapsed,Start,End,NodeList'],capture_output=True,text=True,timeout=45,check=True)
 emit('SUPPLEMENTARY_RECOVERY_JOB',dict(registration=j,workdir=str(r),script_sha256=sha(script),returncode=result.returncode,stdout=result.stdout,stderr=result.stderr,accounting=hist.stdout))
a=subprocess.run(['sacct','-X','-j','242597','-n','-P','-o','JobID,State,ExitCode,Elapsed,Start,End,NodeList'],capture_output=True,text=True,timeout=45,check=True)
emit('SUPPLEMENTARY_DIAGNOSTIC_ACCOUNTING',a.stdout)
RECOVERY
