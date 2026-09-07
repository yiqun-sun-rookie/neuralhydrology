#!/usr/bin/env bash
set -eo pipefail
echo 'channel=kalmannet-daily-perbasin sequence=45 purpose=readonly-historyfix1-runtime-synthetic-terminal-verification'
export PYTHONDONTWRITEBYTECODE=1 PYTHONOPTIMIZE=0
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B -u - <<'PY_COLLECT'
import hashlib, json, os, pathlib, re, subprocess, sys, time
root = pathlib.Path('/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901')
source = root / 'deployments/DAILY_CAMELS_KNET_PER_BASIN_V2_BUNDLE_HISTORYFIX1_DEPLOY_SEQ43/source'
sequence = 45
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
    require(len(data) == 442374 and sha(data) == '737d7044e6c239d16a13d28ce1d7bd62fe8f58c6bd304ee89b3a681edc230c38', 'archive mismatch')
    mb = (source / 'bundle_manifest.json').read_bytes()
    require(sha(mb) == '39b0539bbdc14df2f443c3e6a548952c5ba2fe28bf650cc7be5b12f8bce0ad7f', 'manifest mismatch')
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
import hashlib,json,pathlib
root=pathlib.Path('/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901')
source=pathlib.Path('/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901/deployments/DAILY_CAMELS_KNET_PER_BASIN_V2_BUNDLE_HISTORYFIX1_DEPLOY_SEQ43/source')
old_source=root/'deployments/DAILY_CAMELS_KNET_PER_BASIN_V2_BUNDLE_DEPLOY1_SEQ34/source'
sha=lambda b:hashlib.sha256(b).hexdigest()
def require(condition,message):
    if not condition: raise RuntimeError(message)
expected_runs=[
 'DAILY_CAMELS_KNET_PER_BASIN_PILOT_04105700_A800_TRAIN3_SEQ13',
 'DAILY_CAMELS_KNET_PER_BASIN_PILOT_08070200_A800_TRAIN1_SEQ18',
 'DAILY_CAMELS_KNET_PER_BASIN_PILOT_09035800_A800_TRAIN1_SEQ24',
 'DAILY_CAMELS_KNET_PER_BASIN_PILOT_04105700_V2_20260902_A43_A800_TRAIN1_SEQ41']
failed=root/'runs'/expected_runs[-1]
def preserved_snapshot():
    require(sorted(p.name for p in (root/'runs').iterdir())==sorted(expected_runs),'run namespace drift')
    mb=(old_source/'bundle_manifest.json').read_bytes()
    require(sha(mb)=='5abaa07cfc00e2795a91a8cd70bb793e5cf362971fd04a2de44cbf3e15fa587f','old manifest drift')
    old_manifest=json.loads(mb)
    actual={p.relative_to(old_source).as_posix():p for p in old_source.rglob('*') if p.is_file()}
    require(set(actual)==set(old_manifest['member_sha256'])|{'bundle_manifest.json'},'old deployed inventory drift')
    for name,h in old_manifest['member_sha256'].items():
        require(not actual[name].is_symlink() and sha(actual[name].read_bytes())==h,'old source drift '+name)
    metadata={}
    for name in expected_runs:
        folder=root/'runs'/name
        require(folder.is_dir() and not folder.is_symlink(),'old run absent or linked')
        metadata[name]=[{'path':p.relative_to(folder).as_posix(),'size':p.stat().st_size,'mtime_ns':p.stat().st_mtime_ns}
                        for p in sorted(folder.rglob('*')) if p.is_file()]
    require((failed/'attempts/epoch_001.started.json').is_file(),'old failure marker missing')
    require((failed/'checkpoints/epoch_000.pt').is_file(),'old initial checkpoint missing')
    require(not (failed/'checkpoints/epoch_001.pt').exists() and not (failed/'completion.marker.json').exists(),'old failure was rewritten')
    return {'old_deployment_members':len(actual),'run_names':sorted(expected_runs),
            'old_run_file_metadata':metadata,
            'failed_run_file_sha256':{p.relative_to(failed).as_posix():sha(p.read_bytes()) for p in sorted(failed.rglob('*')) if p.is_file()}}

require(preserved_snapshot()==json.loads((source.parent/'pre_deploy_preserved_snapshot.json').read_text()),'old protected state differs from deployment baseline')
mb=(source/'bundle_manifest.json').read_bytes()
require(sha(mb)=='39b0539bbdc14df2f443c3e6a548952c5ba2fe28bf650cc7be5b12f8bce0ad7f','new manifest drift')
m=json.loads(mb)
actual={p.relative_to(source).as_posix():p for p in source.rglob('*') if p.is_file()}
require(set(actual)==set(m['member_sha256'])|{'bundle_manifest.json'},'new source inventory differs')
require(all(not p.is_symlink() and sha(p.read_bytes())==m['member_sha256'][n] for n,p in actual.items() if n!='bundle_manifest.json'),'new source hash drift')
require(len((source.parent/'daily_camels_knet_per_basin_pilots_v2.tar.gz').read_bytes())==442374 and sha((source.parent/'daily_camels_knet_per_basin_pilots_v2.tar.gz').read_bytes())=='737d7044e6c239d16a13d28ce1d7bd62fe8f58c6bd304ee89b3a681edc230c38','new archive drift')
print(json.dumps({'status':'HISTORYFIX1_PROTECTED_REMOTE_INTEGRITY_PASS','new_source_files':len(actual),'old_run_count':4,'old_failed_job_id':223514,'old_failure_preserved':True,'formal_access_count':0}),flush=True)

support=pathlib.Path('/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901/node_recovery_20260907/historyfix1_runtime_seq44/test_support')
smb=(support/'test_support_manifest.json').read_bytes()
require(sha(smb)=='59c91069fae4a880e559546c0c370b9fbedbd1ee716b6731ac28cd6b75f79d41','test support manifest drift')
sm=json.loads(smb);sa={p.relative_to(support).as_posix():p for p in support.rglob('*') if p.is_file()}
require(set(sa)==set(sm['member_sha256'])|{'test_support_manifest.json'},'test tool inventory drift')
require(all(not p.is_symlink() and sha(p.read_bytes())==sm['member_sha256'][n] for n,p in sa.items() if n!='test_support_manifest.json'),'test tool hash drift')
print(json.dumps({'status':'ISOLATED_TEST_SUPPORT_INTEGRITY_PASS','support_files':len(sa),'support_manifest_sha256':sha(smb)}),flush=True)

import math
audit=root/'node_recovery_20260907/historyfix1_runtime_seq44'
expected_job_id='223532'
expected_baseline_sha256='616a5770539b7db84d9130cc25faf45d3a0f52aa02be0ee1244bbd6746783944'
expected_script_sha256='5776c70ee3b11d0d60ca96daa0bfb77a3dd2e1a6c9d934939d207e5da31001c8'
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
require(baseline['request_sequence']==44 and baseline['new_build_first_runtime_attempt']==1 and baseline['old_failed_training_job_id']==223514 and baseline['old_failed_training_is_not_resumed'] is True and baseline['node']=='ngu203' and baseline['training_submissions']==0,'baseline identity differs')
require(baseline['runtime_script_sha256']==expected_script_sha256 and baseline['runtime_script_bytes']==15609,'baseline runtime script differs')
require(baseline['source_root']==str(source) and baseline['deployed_files']==51,'baseline deployment differs')
require(receipt['request_sequence']==44 and receipt['job_matches']==[expected_job_id] and receipt['submission_exit_code']==0,'submission job binding differs')
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
for name in ['slurm-'+expected_job_id+'.stdout','slurm-'+expected_job_id+'.stderr','history_binding_pytest.stdout','history_binding_pytest.stderr','history_binding_junit.xml','test_support/test_support_manifest.json']+[f'gate_{b}.{s}' for b in ['04105700','08070200','09035800'] for s in ['stdout','stderr']]:
    if (audit/name).exists(): texts[name]=read_registered(name)
    else: print(json.dumps(dict(audit_file=name,exists=False)),flush=True)
metadata=[]
synthetic_file_count=0;synthetic_directory_count=0;synthetic_bytes=0;support_file_count=0;support_bytes=0
for p in sorted(audit.rglob('*')):
    require(not p.is_symlink(),'linked audit member')
    require(p.is_file() or p.is_dir(),'special audit member')
    if 'test_support' in p.relative_to(audit).parts:
        if p.is_file(): support_file_count+=1;support_bytes+=p.stat().st_size
        continue
    if 'synthetic_tmp' in p.relative_to(audit).parts:
        if p.is_file(): synthetic_file_count+=1;synthetic_bytes+=p.stat().st_size
        else: synthetic_directory_count+=1
    else: metadata.append(dict(path=p.relative_to(audit).as_posix(),is_directory=p.is_dir(),size_bytes=p.stat().st_size))
print(json.dumps(dict(audit_inventory_outside_synthetic=metadata,synthetic_inventory_metadata_only=dict(files=synthetic_file_count,directories=synthetic_directory_count,total_bytes=synthetic_bytes),synthetic_checkpoint_contents_returned=0,support_payload_metadata_only=dict(files=support_file_count,total_bytes=support_bytes)),sort_keys=True),flush=True)
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
    check(main[0][1]=='kdpp-v2-historyfix1-runtime44','accounting job name differs')
    check(main[0][2]=='COMPLETED' and main[0][3]=='0:0','job not COMPLETED 0:0')
    check(main[0][5]=='ngu203' and main[0][6:8]==['4','4'],'actual node or CPU allocation differs')
out=texts.get('slurm-'+expected_job_id+'.stdout','')
check('slurm_job_id='+expected_job_id+' hostname=ngu203 CUDA_VISIBLE_DEVICES=' in out,'allocated job identity absent')
check('HISTORYFIX1_RUNTIME_AND_SYNTHETIC_GATE_FINISHED real_gpu_optimizer_steps=0 cpu_toy_optimizer_updates=405 scientific_training_submissions=0' in out,'all-three terminal marker absent')
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

import xml.etree.ElementTree as ET
synthetic_pass=[obj for obj in objects if obj.get('status')=='HISTORYFIX1_SYNTHETIC_CPU_ENTRYPOINT_PASS']
junit_text=texts.get('history_binding_junit.xml','')
junit_cases=[]
try: junit_cases=list(ET.fromstring(junit_text).iter('testcase'))
except ET.ParseError: issues.append('synthetic JUnit missing or malformed')
expected_test_names=["test_v2_history_binding_real_entrypoint_completes_contiguous_cpu_fixture[04105700]","test_v2_history_binding_real_entrypoint_completes_contiguous_cpu_fixture[08070200]","test_v2_history_binding_real_entrypoint_completes_contiguous_cpu_fixture[09035800]","test_v2_history_binding_corrupt_history_stops_before_next_forward_or_update[empty-0]","test_v2_history_binding_corrupt_history_stops_before_next_forward_or_update[missing-1]","test_v2_history_binding_corrupt_history_stops_before_next_forward_or_update[duplicate-1]","test_v2_history_binding_corrupt_history_stops_before_next_forward_or_update[unordered-1]","test_v2_history_binding_corrupt_history_stops_before_next_forward_or_update[pending-0]","test_v2_history_binding_corrupt_history_stops_before_next_forward_or_update[objective-0]","test_v2_history_binding_corrupt_history_stops_before_next_forward_or_update[disk_conflict-1]","test_v2_history_binding_corrupt_history_stops_before_next_forward_or_update[broken_json-0]","test_v2_history_binding_persistence_failure_and_real_resume_preserve_history[0]","test_v2_history_binding_persistence_failure_and_real_resume_preserve_history[1]","test_v2_history_binding_started_without_checkpoint_still_forbids_resume","test_v2_history_binding_guard_rejects_inconsistent_prefix_without_repair[none]","test_v2_history_binding_guard_rejects_inconsistent_prefix_without_repair[empty]","test_v2_history_binding_guard_rejects_inconsistent_prefix_without_repair[missing]","test_v2_history_binding_guard_rejects_inconsistent_prefix_without_repair[duplicate]","test_v2_history_binding_guard_rejects_inconsistent_prefix_without_repair[unordered]","test_v2_history_binding_guard_rejects_inconsistent_prefix_without_repair[pending]","test_v2_history_binding_guard_rejects_inconsistent_prefix_without_repair[boolean_epoch]","test_v2_history_binding_guard_rejects_inconsistent_prefix_without_repair[boolean_steps]","test_v2_history_binding_guard_rejects_inconsistent_prefix_without_repair[wrong_events]","test_v2_history_binding_guard_rejects_inconsistent_prefix_without_repair[nan]","test_v2_history_binding_guard_rejects_inconsistent_prefix_without_repair[infinity]","test_v2_history_binding_guard_rejects_inconsistent_prefix_without_repair[negative_zero]","test_v2_history_binding_guard_rejects_inconsistent_prefix_without_repair[zero_zero]","test_v2_history_binding_guard_rejects_inconsistent_prefix_without_repair[disk_conflict]","test_v2_history_binding_guard_rejects_inconsistent_prefix_without_repair[checkpoint_conflict]"]
actual_test_names=[c.attrib.get('name') for c in junit_cases]
check(len(actual_test_names)==len(set(actual_test_names))==29 and sorted(actual_test_names)==sorted(expected_test_names),'29 exact synthetic test names required')
check(all(c.find('failure') is None and c.find('error') is None and c.find('skipped') is None for c in junit_cases),'synthetic failure, error or skip exists')
check(len(synthetic_pass)==1,'one synthetic acceptance object required')
if len(synthetic_pass)==1:
    s=synthetic_pass[0]
    check(s.get('tests')==29 and s.get('failures')==s.get('errors')==s.get('skips')==0,'synthetic count differs')
    check(s.get('scientific_optimizer_updates')==0 and s.get('synthetic_toy_optimizer_updates_asserted_by_tests')==405,'synthetic update meaning differs')
    check(s.get('junit_sha256')==sha(junit_text.encode()),'synthetic JUnit provenance differs')
toolorigins=[o for o in objects if o.get('status')=='ISOLATED_TEST_TOOL_ORIGINS_PASS']
check(len(toolorigins)==1,'exact CPU test tool import evidence absent')
if len(toolorigins)==1:
    t=toolorigins[0];check(t.get('versions')=={'pytest':'8.3.5','pluggy':'1.6.0','iniconfig':'2.1.0','packaging':'25.0'},'tool versions differ')
    check(set(t.get('origins',{}))=={'pytest','pluggy','iniconfig','packaging'} and all(pathlib.Path(p).is_relative_to(audit/'test_support') for p in t.get('origins',{}).values()),'tool actual import origin differs')
    check(t.get('visible_cuda_devices_for_synthetic_cpu')==0,'synthetic CPU process exposed GPU')
    check(t.get('python_executable')=='/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python','test interpreter executable differs')
    check(all(pathlib.Path(t.get(k,'/')).is_relative_to(pathlib.Path('/data1/home/sunyiq/miniconda3/envs/nh_final')) for k in ('torch_origin','numpy_origin')),'scientific dependency origins differ')
check(len([o for o in objects if o.get('status')=='ISOLATED_TEST_SUPPORT_INTEGRITY_PASS'])==2,'pre/post test support integrity evidence absent')

integrity_objects=[o for o in objects if o.get('status')=='HISTORYFIX1_PROTECTED_REMOTE_INTEGRITY_PASS']
check(len(integrity_objects)==2,'pre/post real job protected integrity evidence missing')
check(not texts.get('slurm-'+expected_job_id+'.stderr','').strip(),'job stderr nonempty requires review')
check(not texts.get('history_binding_pytest.stderr','').strip(),'synthetic stderr nonempty requires review')

required_terminal_texts=['slurm-'+expected_job_id+'.stdout','slurm-'+expected_job_id+'.stderr','history_binding_pytest.stdout','history_binding_pytest.stderr','history_binding_junit.xml','test_support/test_support_manifest.json']+[f'gate_{b}.{s}' for b in ['04105700','08070200','09035800'] for s in ['stdout','stderr']]
check(len(required_terminal_texts)==12 and all(name in texts for name in required_terminal_texts),'all 12 terminal text artifacts must exist')
required_empty_stderr=['slurm-'+expected_job_id+'.stderr','history_binding_pytest.stderr']+[f'gate_{b}.stderr' for b in ['04105700','08070200','09035800']]
for name in required_empty_stderr:
    check(name in texts and texts[name]=='','required stderr must exist and contain exactly zero bytes: '+name)

active=state in ['PENDING','RUNNING','CONFIGURING','COMPLETING']
status='HISTORYFIX1_RUNTIME_AND_SYNTHETIC_PASS_REQUIRES_INDEPENDENT_ACCEPTANCE' if not issues else ('RUNTIME_GATE_NOT_TERMINAL' if active else 'RUNTIME_GATE_FAILED_OR_UNVERIFIABLE')
print(json.dumps(dict(status=status,request_sequence=sequence,submission_sequence=44,job_id=expected_job_id,node='ngu203',accounting_state=state,baseline_sha256=expected_baseline_sha256,runtime_script_sha256=expected_script_sha256,deployed_file_count=51,gate_count=len(gates),gate_results=gates,synthetic_test_cases=len(junit_cases),synthetic_toy_optimizer_updates_asserted_by_tests=405,scientific_optimizer_updates=0,issues=issues,training_submissions=0,runtime_submissions=0,task_file_writes=0,formal_evaluation_access_count=0),sort_keys=True,allow_nan=False),flush=True)

PY_COLLECT
