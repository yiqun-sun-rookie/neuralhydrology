#!/usr/bin/env bash
set -eo pipefail
echo 'channel=kalmannet-daily-perbasin sequence=40 purpose=readonly-job223511-runtime-terminal-verification'
export PYTHONDONTWRITEBYTECODE=1 PYTHONOPTIMIZE=0
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B -u - <<'PY_COLLECT'
import hashlib, json, os, pathlib, re, subprocess, sys, time
root = pathlib.Path('/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901')
source = root / 'deployments/DAILY_CAMELS_KNET_PER_BASIN_V2_BUNDLE_DEPLOY1_SEQ34/source'
sequence = 40
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

import math
audit=root/'node_recovery_20260907/task6_runtime_recovery1_seq39'
expected_job_id='223511'
expected_baseline_sha256='241848390d615e584ff988060a47082cf49718bb09225480426f26e8fc84b867'
expected_script_sha256='fba1762805311c2a28efd048dcfc61f47cf003c407671a02606f27dfff217913'
require(audit.is_dir() and audit.resolve()==audit and not audit.is_symlink(),'audit directory missing or linked')
def read_registered(name, expected_sha=None):
    p=audit/name
    require(p.is_file() and not p.is_symlink() and p.resolve()==p,'registered audit text missing or linked: '+name)
    b=p.read_bytes()
    require(len(b)<=4*1024*1024,'audit text exceeds registered collector limit: '+name)
    if expected_sha: require(sha(b)==expected_sha,'registered audit hash mismatch: '+name)
    text=b.decode('utf-8')
    print(json.dumps(dict(audit_file=name,size_bytes=len(b),sha256=sha(b),text=text),sort_keys=True),flush=True)
    return text
baseline=json.loads(read_registered('pre_submit_baseline.json',expected_baseline_sha256))
receipt=json.loads(read_registered('submission_receipt.json'))
read_registered('runtime_gate.sh',expected_script_sha256)
require(baseline['request_sequence']==39 and baseline['recovery_attempt']==1 and baseline['node']=='ngu203' and baseline['training_submissions']==0,'baseline identity differs')
require(baseline['runtime_script_sha256']==expected_script_sha256 and baseline['runtime_script_bytes']==4896,'baseline runtime script differs')
require(baseline['source_root']==str(source) and baseline['deployed_files']==51,'baseline deployment differs')
require(receipt['request_sequence']==39 and receipt['job_matches']==[expected_job_id] and receipt['submission_exit_code']==0,'submission job binding differs')
require(receipt['baseline_sha256']==expected_baseline_sha256 and receipt['runtime_script_sha256']==expected_script_sha256 and receipt['training_submissions']==0 and receipt['runtime_submissions']==1,'submission receipt binding differs')
queries={}
for label,args in [
    ('RUNTIME_JOB_SQUEUE',['squeue','-h','-j',expected_job_id,'-o','%i|%j|%T|%P|%N|%R']),
    ('RUNTIME_JOB_SACCT',['sacct','-n','-P','-j',expected_job_id,'--format=JobID,JobName%80,State,ExitCode,Elapsed,NodeList,AllocCPUS,ReqCPUS']),
    ('RUNTIME_JOB_SCONTROL',['scontrol','show','job',expected_job_id]),
    ('CURRENT_TASK_JOBS',['squeue','-h','-u',os.environ['USER'],'-o','%i|%200j|%T|%P|%N|%R'])]:
    r=run(args)
    queries[label]=r
    emit(label,r)
texts={}
for name in ['slurm-'+expected_job_id+'.stdout','slurm-'+expected_job_id+'.stderr']+[f'gate_{b}.{s}' for b in ['04105700','08070200','09035800'] for s in ['stdout','stderr']]:
    if (audit/name).exists(): texts[name]=read_registered(name)
    else: print(json.dumps(dict(audit_file=name,exists=False)),flush=True)
metadata=[]
for p in sorted(audit.rglob('*')):
    require(not p.is_symlink(),'linked audit member')
    require(p.is_file() or p.is_dir(),'special audit member')
    metadata.append(dict(path=p.relative_to(audit).as_posix(),is_directory=p.is_dir(),size_bytes=p.stat().st_size))
print(json.dumps(dict(audit_inventory=metadata),sort_keys=True),flush=True)
current_runs=sorted(p.name for p in (root/'runs').iterdir())
print(json.dumps(dict(baseline_before_runs=baseline['before_runs'],current_runs=current_runs,run_names_unchanged=current_runs==baseline['before_runs'])),flush=True)
require(current_runs==baseline['before_runs'],'training run namespace changed during non-training gate')
require((audit/'output_parent').is_dir() and not any((audit/'output_parent').iterdir()),'non-training output parent is not empty')
locks=root/'status/locks'
require(locks.is_dir() and not locks.is_symlink() and not any(locks.iterdir()),'execution locks changed')
verify_source()
rows=[line.split('|') for line in queries['RUNTIME_JOB_SACCT'].stdout.decode().splitlines() if line.strip()]
main=[row for row in rows if row[0]==expected_job_id]
issues=[]
def check(value,message):
    if not value: issues.append(message)
check(queries['RUNTIME_JOB_SACCT'].returncode==0 and len(main)==1,'one complete accounting row required')
state=main[0][2] if len(main)==1 else 'UNVERIFIABLE'
if len(main)==1:
    check(len(main[0])>=8,'accounting row lacks resources')
    check(main[0][1]=='kdpp-v2-runtime-recovery1-seq39','accounting job name differs')
    check(main[0][2]=='COMPLETED' and main[0][3]=='0:0','job not COMPLETED 0:0')
    check(main[0][5]=='ngu203' and main[0][6:8]==['4','4'],'actual node or CPU allocation differs')
out=texts.get('slurm-'+expected_job_id+'.stdout','')
check('slurm_job_id='+expected_job_id+' hostname=ngu203 CUDA_VISIBLE_DEVICES=' in out,'allocated job identity absent')
check('TASK6_THREE_RUNTIME_CHECKS_FINISHED optimizer_steps=0 training_submissions=0' in out,'all-three terminal marker absent')
for token in ['JobId='+expected_job_id,'Requeue=0','Restarts=0','NodeList=ngu203','NumNodes=1','NumCPUs=4']:
    check(token in out,'runtime controller resource token absent: '+token)
objects=[]
for line in out.splitlines():
    if line.startswith('{'):
        try: objects.append(json.loads(line))
        except json.JSONDecodeError: pass
resources={obj['stage']:obj for obj in objects if 'stage' in obj}
pre=resources.get('whole_node_existing_compute_processes',{})
check(pre.get('exit_code')==0 and isinstance(pre.get('stdout'),str) and pre.get('stdout').strip()=='','pre-existing compute process check not empty success')
check(resources.get('host_memory',{}).get('MemAvailable',0)>=32*1024**3,'host memory guard absent or insufficient')
gpu=resources.get('allocated_device_identity',{})
check(gpu.get('python')=='3.11.13' and gpu.get('numpy')=='2.3.3' and gpu.get('torch','').split('+')[0]=='2.4.0','interpreter identity differs')
check(gpu.get('cuda_available') is True and gpu.get('visible_cuda_devices')==1 and gpu.get('gpu_name')=='NVIDIA A800-SXM4-80GB','actual allocated GPU identity differs')
check(gpu.get('gpu_free_bytes',0)>=64*1024**3,'allocated memory guard absent or insufficient')
gates={}
for basin,dim in [('04105700',7),('08070200',11),('09035800',18)]:
    check('RUNTIME_GATE_END basin='+basin+' exit_code=0' in out,'gate exit marker missing: '+basin)
    raw=texts.get('gate_'+basin+'.stdout','')
    try: gate=json.loads(raw)
    except json.JSONDecodeError:
        issues.append('gate output not exactly one JSON document: '+basin)
        continue
    gates[basin]=gate
    check(gate.get('schema_version')=='daily_camels_knet_per_basin_runtime_gate_v2','gate schema differs: '+basin)
    check(gate.get('experiment_family')=='DAILY_CAMELS_KNET_PER_BASIN_PILOT_V2_20260902','gate family differs: '+basin)
    check(gate.get('status')=='PASS' and gate.get('basin_id')==basin and gate.get('state_dimension')==dim,'gate status or geometry differs: '+basin)
    check(gate.get('device')=='cuda' and gate.get('gpu_name')=='NVIDIA A800-SXM4-80GB','gate device differs: '+basin)
    for key in ['exact_active_mask_no_padding','causal_future_observation_test','finite_nonzero_gradient_test','checkpoint_restore_test','epoch_zero_joint_resume_test','correction_cap_enabled']:
        check(gate.get(key) is True,'gate boolean differs: '+basin+':'+key)
    value=gate.get('segment_objective')
    check(isinstance(value,(float,int)) and math.isfinite(value),'gate objective not finite: '+basin)
    check(gate.get('segment_target_count_by_lead')=={'1':102,'2':102,'3':102},'gate target counts differ: '+basin)
    check(gate.get('optimizer_steps')==0 and gate.get('formal_evaluation_access_count')==0,'gate update or formal access count nonzero: '+basin)
    check(gate.get('correction_cap_in_state_scale_units')==3.0 and gate.get('divergence_stop_checkpoint_ratio')==100.0 and gate.get('divergence_stop_post_step_ratio')==100.0,'gate numerical policy differs: '+basin)
    check(bool(re.fullmatch('[a-f0-9]{64}',gate.get('temporary_checkpoint_sha256',''))),'temporary checkpoint fingerprint missing: '+basin)
active=state in ['PENDING','RUNNING','CONFIGURING','COMPLETING']
status='TASK6_RUNTIME_GATE_PASS_REQUIRES_INDEPENDENT_ACCEPTANCE' if not issues else ('RUNTIME_GATE_NOT_TERMINAL' if active else 'RUNTIME_GATE_FAILED_OR_UNVERIFIABLE')
print(json.dumps(dict(status=status,request_sequence=sequence,submission_sequence=39,job_id=expected_job_id,node='ngu203',accounting_state=state,baseline_sha256=expected_baseline_sha256,runtime_script_sha256=expected_script_sha256,deployed_file_count=51,gate_count=len(gates),gate_results=gates,issues=issues,training_submissions=0,runtime_submissions=0,task_file_writes=0,formal_evaluation_access_count=0),sort_keys=True,allow_nan=False),flush=True)

PY_COLLECT
