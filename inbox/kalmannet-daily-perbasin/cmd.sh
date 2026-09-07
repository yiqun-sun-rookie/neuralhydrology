#!/usr/bin/env bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1 PYTHONOPTIMIZE=0
echo 'channel=kalmannet-daily-perbasin sequence=42 purpose=readonly-first-training-progress-no-submit'
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B -u - <<'PY_PROGRESS'
import hashlib, json, os, pathlib, re, subprocess, sys, time
root = pathlib.Path('/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901')
source = root / 'deployments/DAILY_CAMELS_KNET_PER_BASIN_V2_BUNDLE_DEPLOY1_SEQ34/source'
sequence = 42
sha = lambda b: hashlib.sha256(b).hexdigest()
def require(value, message):
    if not value: raise RuntimeError(message)
def run(args, **kwargs):
    kwargs.setdefault('timeout', 45)
    return subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs)
def emit(label, result):
    print(label, 'exit_code=' + str(result.returncode), flush=True)
    print(result.stdout.decode('utf-8'), end='', flush=True)
    print(result.stderr.decode('utf-8'), end='', file=sys.stderr, flush=True)
require(root.is_dir() and root.resolve() == root and not root.is_symlink(), 'registered root differs')
require(source.is_dir() and source.resolve() == source and not source.is_symlink(), 'source root differs')
def verify_source():
    archive = source.parent / 'daily_camels_knet_per_basin_pilots_v2.tar.gz'
    require(archive.is_file() and not archive.is_symlink(), 'archive missing or linked')
    data = archive.read_bytes()
    require(len(data) == 438532 and sha(data) == '1b78bbae823d55859391a6cdee3b9fbe8a40203e5140b8795105a8617592b7fd', 'archive mismatch')
    mb = (source / 'bundle_manifest.json').read_bytes()
    require(sha(mb) == '5abaa07cfc00e2795a91a8cd70bb793e5cf362971fd04a2de44cbf3e15fa587f', 'manifest mismatch')
    manifest = json.loads(mb)
    actual = {}
    for path in source.rglob('*'):
        require(not path.is_symlink(), 'source contains link')
        if path.is_file(): actual[path.relative_to(source).as_posix()] = path
        else: require(path.is_dir(), 'source contains special member')
    require(len(actual) == 51 and set(actual) == set(manifest['member_sha256']) | {'bundle_manifest.json'}, 'source members differ')
    require(manifest['member_count'] == 50 and manifest['formal_evaluation_member_count'] == manifest['historical_evaluation_member_count'] == 0, 'member policy mismatch')
    for name, expected in manifest['member_sha256'].items():
        content = actual[name].read_bytes()
        require(sha(content) == expected and len(content) == manifest['member_size_bytes'][name], 'payload mismatch: ' + name)
    print('DEPLOYED_51_FILE_HASH_CHECK=PASS', flush=True)
verify_source()


execution_id='DAILY_CAMELS_KNET_PER_BASIN_PILOT_04105700_V2_20260902_A43_A800_TRAIN1_SEQ41'
job_id='223514'
expected_baseline_sha256='b17fa4af9b6479aa7058a6b7afbd0c381519aac8def4bdf13c8e48cfddfd6ee4'
launch=root/'node_recovery_20260907/train_04105700_seq41'
run_directory=root/'runs'/execution_id
status=root/'status'
require(launch.is_dir() and launch.resolve()==launch,'registered training launch missing or linked')
def read_text(path,label,full=True):
    require(path.is_file() and not path.is_symlink() and path.resolve()==path,'registered text missing or linked: '+label)
    b=path.read_bytes()
    require(len(b)<=4*1024*1024,'text exceeds safe read limit: '+label)
    item=dict(file=label,size_bytes=len(b),sha256=sha(b))
    t=b.decode('utf-8')
    if full: item['text']=t
    print(json.dumps(item,sort_keys=True),flush=True)
    return t,item
baseline_text,baseline_meta=read_text(launch/'pre_submit_baseline.json','launch/pre_submit_baseline.json')
require(baseline_meta['sha256']==expected_baseline_sha256,'training submission baseline differs')
baseline=json.loads(baseline_text)
submission=json.loads(read_text(launch/'submission_receipt.json','launch/submission_receipt.json')[0])
require(submission['job_matches']==[job_id] and submission['baseline_sha256']==expected_baseline_sha256 and submission['execution_id']==execution_id,'training job binding differs')
require(baseline['execution_id']==execution_id and baseline['basin_id']=='04105700' and baseline['node']=='ngu203' and baseline['training_attempt']==1,'training baseline identity differs')
wrapper=read_text(launch/'train.sh','launch/train.sh',full=False)[1]
require(wrapper['sha256']==baseline['node_wrapper_sha256'] and wrapper['size_bytes']==baseline['node_wrapper_bytes'],'training node wrapper differs')
accounting=None
for label,args in [
('TRAINING_JOB_SQUEUE',['squeue','-h','-j',job_id,'-o','%i|%j|%T|%P|%N|%R']),
('TRAINING_JOB_SACCT',['sacct','-n','-P','-j',job_id,'--format=JobID,JobName%80,State,ExitCode,Elapsed,NodeList,AllocCPUS,ReqCPUS']),
('TRAINING_JOB_SCONTROL',['scontrol','show','job',job_id]),
('CURRENT_USER_QUEUE',['squeue','-h','-u',str(os.getuid()),'-o','%i|%200j|%T|%N'])]:
    r=run(args)
    emit(label,r)
    if label=='TRAINING_JOB_SACCT': accounting=r
logs={}
for suffix in ['.slurm-'+job_id+'.stdout','.slurm-'+job_id+'.stderr','.entry.json','.audit.json','.cgroup.txt']:
    p=status/(execution_id+suffix)
    if p.exists(): logs[suffix]=read_text(p,'status/'+p.name)[0]
    else: print(json.dumps(dict(file='status/'+p.name,exists=False)),flush=True)
gpu_log=status/(execution_id+'.gpu.csv')
if gpu_log.exists():
    require(gpu_log.is_file() and not gpu_log.is_symlink(),'GPU sample log linked')
    size=gpu_log.stat().st_size
    with gpu_log.open('rb') as f:
        f.seek(max(0,size-4096))
        tail=f.read().decode('utf-8')
    print(json.dumps(dict(file='status/'+gpu_log.name,size_bytes=size,tail=tail,tail_is_not_full_file=True)),flush=True)
current_runs=sorted(p.name for p in (root/'runs').iterdir())
require(set(current_runs) in [set(baseline['before_runs']),set(baseline['before_runs'])|{execution_id}],'unrelated training run namespace change')
print(json.dumps(dict(old_run_names_preserved=all(x in current_runs for x in baseline['before_runs']),current_runs=current_runs)),flush=True)
hist=[]
preflight=None
checkpoint_metadata=[]
if run_directory.exists():
    require(run_directory.is_dir() and run_directory.resolve()==run_directory and not run_directory.is_symlink(),'training run linked or invalid')
    inventory=[]
    for p in sorted(run_directory.rglob('*')):
        require(not p.is_symlink() and (p.is_file() or p.is_dir()),'invalid training run member')
        inventory.append(dict(path=p.relative_to(run_directory).as_posix(),is_directory=p.is_dir(),size_bytes=p.stat().st_size))
    print(json.dumps(dict(run_inventory=inventory),sort_keys=True),flush=True)
    checkpoint_metadata=[x for x in inventory if x['path'].startswith('checkpoints/') and not x['is_directory']]
    for name in ['preflight.json','epoch_history.json','completion.marker.json','manifest.sha256.json','result_summary.json','divergence_event.json','unregistered_numeric_failure_event.json']:
        p=run_directory/name
        if not p.exists():
            print(json.dumps(dict(file='run/'+name,exists=False)),flush=True)
            continue
        text,meta=read_text(p,'run/'+name,full=name not in ['epoch_history.json','result_summary.json'])
        obj=json.loads(text)
        if name=='preflight.json':
            preflight=obj
            require(obj['execution_id']==execution_id and obj['experiment_id']==baseline['experiment_id'] and obj['configuration_sha256']==baseline['configuration_sha256'] and obj['source_sha256']==baseline['source_sha256'],'actual training preflight identity differs')
            require(obj['device_name']=='NVIDIA A800-SXM4-80GB' and obj['formal_evaluation_enabled'] is False and obj['historical_evaluation_access_authorized'] is False,'actual training device or formal policy differs')
        if name=='epoch_history.json':
            require(isinstance(obj,list),'history must be a list')
            hist=obj
            print(json.dumps(dict(history_file_sha256=meta['sha256'],history_row_count=len(hist),history_first_row=hist[0] if hist else None,history_last_two_rows=hist[-2:],history_epoch_statuses=[{k:row.get(k) for k in ['epoch','epoch_status','validation_status','optimizer_steps','training_forecast_error_events']} for row in hist],history_projection_not_full_file=True),sort_keys=True,allow_nan=False),flush=True)
        if name=='result_summary.json':
            print(json.dumps(dict(result_summary_file_sha256=meta['sha256'],result_summary_without_history={k:v for k,v in obj.items() if k!='history'},omitted_history= 'history' in obj),sort_keys=True,allow_nan=False),flush=True)
else:
    print(json.dumps(dict(run_directory_exists=False)),flush=True)
verify_source()
rows=[line.split('|') for line in accounting.stdout.decode().splitlines() if line.startswith(job_id+'|')] if accounting is not None else []
state=rows[0][2] if accounting.returncode==0 and len(rows)==1 else 'UNVERIFIABLE'
completed=[row for row in hist if isinstance(row.get('epoch'),int) and row.get('validation_status')=='FINITE' and row.get('epoch_status')=='COMPLETED']
max_completed=max([row['epoch'] for row in completed],default=None)
print(json.dumps(dict(status='READONLY_TRAINING_PROGRESS_SNAPSHOT_NOT_TERMINAL_ACCEPTANCE',request_sequence=sequence,submission_sequence=41,job_id=job_id,execution_id=execution_id,basin_id='04105700',accounting_state=state,maximum_completed_epoch=max_completed,history_rows=len(hist),has_preflight=preflight is not None,checkpoint_file_count=len(checkpoint_metadata),initial_checkpoint_exists=any(x['path']=='checkpoints/epoch_000.pt' and x['size_bytes']>0 for x in checkpoint_metadata),training_submissions=0,runtime_submissions=0,task_file_writes=0,checkpoint_downloads=0,formal_evaluation_access_count=0,terminal_independent_acceptance=False),sort_keys=True),flush=True)

PY_PROGRESS
