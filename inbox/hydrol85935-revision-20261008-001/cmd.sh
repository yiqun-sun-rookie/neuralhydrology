#!/usr/bin/env bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - <<'PY'
import datetime,hashlib,json,os,re,subprocess,tarfile
from pathlib import Path
ROOT=Path('/data1/home/sunyiq/hydrol85935_revision_20261008_001')
NEW=Path('/data1/home/sunyiq/hydrol85935_revision_20261008_001/control/hybrid_v013_20261014_001')
PREVIOUS=ROOT/'control/hybrid_v012_20261013_001'
SCHED=ROOT/'control/hybrid_v009_20261012_001'
WF=ROOT/'control/workflow_v010_20261012_001'
PAYLOAD=Path('/data1/home/sunyiq/hpc_mailbox/inbox/hydrol85935-revision-20261008-001/payload/hybrid_v013_20261014_001.tar.gz')
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def save(p,v):
    with p.open('x') as f: json.dump(v,f,indent=2)
def emit(k,v): print(k+' '+json.dumps(v),flush=True)
def query(cmd):
    r=subprocess.run(cmd,text=True,capture_output=True,timeout=45)
    assert r.returncode==0,(cmd,r.stdout,r.stderr)
    return r.stdout
assert ROOT.resolve()==ROOT and (ROOT/'OWNER').read_text().strip()=='hydrol85935_revision_20261008_001'
assert sha(PAYLOAD)=='44b367430f47f511585b8f1eba5e3438070047c16d4309cff0e87bf1741d48fe'
assert not NEW.exists(),'Existing remote transaction: retrieve evidence, never replay'
with tarfile.open(PAYLOAD) as archive:
    members=archive.getmembers()
    assert all(m.isfile() and Path(m.name).name==m.name for m in members)
    blobs={m.name:archive.extractfile(m).read() for m in members}
manifest=json.loads(blobs['payload_files.json'])
assert set(blobs)==set(manifest)|{'payload_files.json'}
for name,h in manifest.items(): assert hashlib.sha256(blobs[name]).hexdigest()==h
registered=json.loads(blobs['registered_job_identity.json'])
scope=json.loads(blobs['delegation_scope.json'])
old=json.loads(blobs['previous_assignment.json']);new=json.loads(blobs['assignment.json'])
assert hashlib.sha256(blobs['previous_assignment.json']).hexdigest()=='71e22779e3088b45e91df4bbd09c3becf592eaece9bd44d158ce306ef72c31c6'
assert sha(PREVIOUS/'assignment.json')=='71e22779e3088b45e91df4bbd09c3becf592eaece9bd44d158ce306ef72c31c6'
assert new['local_assignments'][:-1]==old['local_assignments']
assert new['hpc_tasks'][0]==old['hpc_tasks'][0] and new['hpc_tasks'][2:]==old['hpc_tasks'][2:]
assert old['hpc_tasks'][1]['basins']==scope['basins']+new['hpc_tasks'][1]['basins']
assert old['hpc_tasks'][1]['combinations']==new['hpc_tasks'][1]['combinations']==scope['combinations']
assert (new['hpc_tasks'][1]['index'],new['hpc_tasks'][1]['basin_start'],new['hpc_tasks'][1]['basin_count'])==(1,81,19)
assert not new['hpc_tasks'][1].get('delegated_to')
local=json.loads(blobs['claimed_local_assignment.json'])
assert new['local_assignments'][-1]['sha256']==manifest['claimed_local_assignment.json']
assert local['basins']==scope['basins'] and local['combinations']==scope['combinations'] and local['model']==scope['model']
def allocation(a):
    groups=[{(c,b) for c in x['combinations'] for b in x['basins']} for x in a['local_assignments']]
    groups.append({(c,b) for t in a['hpc_tasks'] for c in t['combinations'] for b in t['basins']})
    union=set()
    for group in groups:
        assert not union&group,'Overlapping allocation'
        union|=group
    assert len(union)==27612
    return union
assert allocation(new)==allocation(old)
assert new['hpc_counts']==dict(attacks=26721,clean=3105,restore_series=12420,trainings=3)
assert new['local_counts']==dict(attacks=891,clean=81,restore_series=324,trainings=0)
assert new['hpc_training_seeds']==old['hpc_training_seeds']==[100,200,300]
def training_accounting():
    text=query(['sacct','-X','-j','241335','-n','-P','-o','JobID,State,ExitCode,Elapsed,Start,End,NodeList'])
    rows={x.split('|')[0]:x.split('|') for x in text.splitlines() if x.strip()}
    assert all(rows.get('241335_'+str(i),['','',''])[1:3]==['COMPLETED','0:0'] for i in range(3)),rows
    prior=json.loads(blobs['completed_training_prior_identity.json'])['fields']
    for k,v in registered['241335'].items(): assert prior[k]==v,(k,prior.get(k),v)
    for i in range(3):
        paths=list((PREVIOUS/'stage_results').glob('train_'+str(i)+'_*.json'))
        assert len(paths)==1 and json.loads(paths[0].read_text())['status']=='PASS'
    return dict(stdout=text,prior_identity=prior,terminal_seeds=[100,200,300])
def jobs_check():
    terminal=training_accounting(); rows={}
    for jid,expected in registered.items():
        if jid=='241335':
            rows[jid]=dict(state='COMPLETED',terminal_accounting=terminal,prior_identity_verified=True)
            continue
        text=query(['scontrol','show','job','-o',jid])
        value=dict(re.findall(r'(\S+?)=(\S*)',text))
        assert value['JobId']==jid and value['JobState']=='PENDING',(jid,value)
        assert value.get('Restarts','0')=='0' and value.get('RunTime')=='00:00:00',(jid,value)
        for k,v in expected.items():
            if jid=='241336' and k=='Dependency':
                assert value.get(k) in (v,'(null)'),'Completed training dependency must remain or resolve naturally'
            else: assert value.get(k)==v,(jid,k,value.get(k),v)
        rows[jid]=dict(fields=value,raw=text)
    # The entire attack array must still be wholly unstarted, including candidate task1.
    text=query(['sacct','-X','-j','241336','-n','-P','-o','JobID,State,ExitCode,Elapsed,Start,End,NodeList'])
    accounting=[x.split('|') for x in text.splitlines() if x.strip()]
    assert accounting and all(x[1]=='PENDING' and x[3]=='00:00:00' and x[4]=='Unknown' and x[5]=='Unknown' for x in accounting),accounting
    rows['attack_array_history']=dict(stdout=text,no_task_started=True)
    return rows
def unused():
    execution=ROOT/'execution/hpc_v009'
    for b in scope['basins']:
        assert not (execution/'records/clean'/scope['model']/b).exists(),b
        for cid in scope['combinations']:
            assert not (execution/'records/attacks'/cid/b).exists(),(cid,b)
    ledger=execution/'records/ledger.jsonl'; lines=0
    if ledger.exists():
        for line in ledger.open():
            if line.strip():
                row=json.loads(line);lines+=1
                assert not (str(row.get('basin_id')) in scope['basins'] and
                    (row.get('combination_id') in scope['combinations'] or row.get('model_id')==scope['model'])),row
    controls=list((ROOT/'control').glob('hybrid_v*'))
    for control in controls:
        assert not list((control/'stage_results').glob('attacks_1_*.json')),'Candidate task has receipt history '+str(control)
        assert not (control/'hpc_packet_001').exists(),'Prior HPC package exists; cannot assume unstarted scope'
    assert not list((SCHED/'logs').glob('attacks-241336_1.*')),'Candidate has scheduler log history'
    assert not (WF/'hpc_packet_001').exists()
    return dict(no_output=True,no_stage_or_scheduler_log_history=True,no_failed_or_uncomputable_ledger_occupancy=True,
                ledger_lines_checked=lines,historical_control_roots=[str(x) for x in controls],scope=scope)
before=jobs_check(); empty_before=unused()
assert sha(SCHED/'worker.py')==manifest['previous_worker_bridge.py']
assert sha(WF/'federated_v010.py')==manifest['previous_export_bridge.py']
emit('BACKFILL_PRECHECK',dict(scheduler=before,candidate=empty_before))
NEW.mkdir()
for name,data in blobs.items():
    with (NEW/name).open('xb') as f:f.write(data)
save(NEW/'scheduler_before.json',before);save(NEW/'candidate_before.json',empty_before)
entries=[dict(path=str(SCHED/'worker.py'),original_sha256=sha(SCHED/'worker.py'),new_sha256=manifest['worker_bridge.py'],source='worker_bridge.py'),
         dict(path=str(WF/'federated_v010.py'),original_sha256=sha(WF/'federated_v010.py'),new_sha256=manifest['export_bridge.py'],source='export_bridge.py')]
save(NEW/'deployment_transaction.json',dict(status='PREPARED',entrypoints=entries,assignment_sha256=manifest['assignment.json'],no_scheduler_mutation=True))
jobs_check(); unused()
for entry in reversed(entries):
    target=Path(entry['path']);assert sha(target)==entry['original_sha256']
    temp=target.with_name(target.name+'.v013.tmp')
    with temp.open('xb') as f:f.write(blobs[entry['source']])
    os.replace(temp,target);assert sha(target)==entry['new_sha256']
after=jobs_check();empty_after=unused()
for jid in registered:
    if jid!='241335':
        for key in ['Command','WorkDir','NumCPUs','CPUs/Task','TresPerNode','Dependency','SubmitTime','ArrayTaskId','ArrayTaskThrottle','Restarts']:
            assert before[jid]['fields'].get(key)==after[jid]['fields'].get(key),(jid,key)
save(NEW/'scheduler_after.json',after);save(NEW/'candidate_after.json',empty_after)
confirmation=dict(status='DEPLOYMENT_CONFIRMED',assignment_sha256=manifest['assignment.json'],delegation_scope=scope,
    entrypoints=entries,old_full_jobs_held=True,existing_job_ids_unchanged=True,
    dependencies_resources_submit_times_unchanged=True,no_scheduler_mutation=True,
    scientific_code_modified=False,other_experiments_modified=False,
    candidate_before=empty_before,candidate_after=empty_after,
    terminal_training_seeds=[100,200,300],union_count=27612,mutually_exclusive=True,
    remote_utc=datetime.datetime.now(datetime.timezone.utc).isoformat())
save(NEW/'deployment_confirmation.json',confirmation)
emit('CPU_BACKFILL_DEPLOYMENT',confirmation)

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
folder = root / 'control/hybrid_v013_20261014_001'
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
folder=root/'control/hybrid_v013_20261014_001';scheduler_folder=root/'control/hybrid_v009_20261012_001';execution=root/'execution/hpc_v009'
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
 for p in [root/'control/hybrid_v013_20261014_001/hpc_packet_001/index.json',t/'control/parent_binding_v010.json',t/'control/new_models_verified.json',t/'control/resource_pilot.json',t/'reports/coverage_and_summary.json']:
  if p.is_file():emit('WORKFLOW_RESULT',dict(path=str(p),sha256=hashlib.sha256(p.read_bytes()).hexdigest(),value=json.loads(p.read_text())))
PY
