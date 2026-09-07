#!/usr/bin/env bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1 PYTHONOPTIMIZE=0
printf '%s\n' 'channel=kalmannet-daily-perbasin sequence=66 purpose=authorized-historyfix1-third-basin-training'
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B -u - <<'PY_SUBMISSION'
import hashlib, json, os, pathlib, re, subprocess, sys, time
root = pathlib.Path('/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901')
source = root / 'deployments/DAILY_CAMELS_KNET_PER_BASIN_V2_BUNDLE_HISTORYFIX1_DEPLOY_SEQ43/source'
sequence = 66
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
completed_first_run='DAILY_CAMELS_KNET_PER_BASIN_PILOT_04105700_V2_20260902_A43_HISTORYFIX1_A800_TRAIN1_SEQ57'
completed_second_run='DAILY_CAMELS_KNET_PER_BASIN_PILOT_08070200_V2_20260902_A44_HISTORYFIX1_A800_TRAIN1_SEQ62'
failed=root/'runs'/expected_runs[-1]
def preserved_snapshot():
    require(sorted(p.name for p in (root/'runs').iterdir())==sorted(expected_runs+[completed_first_run,completed_second_run]),'run namespace drift')
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

old_runtime=pathlib.Path('/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901/node_recovery_20260907/historyfix1_runtime_seq44')
old_runtime_texts={"pre_submit_baseline.json":{"bytes":1613,"sha256":"616a5770539b7db84d9130cc25faf45d3a0f52aa02be0ee1244bbd6746783944"},"submission_receipt.json":{"bytes":368,"sha256":"24a1fc985979846c1a046dbf8d3b35372a5d1a46f8bd3bb8a1521839aec570a9"},"runtime_gate.sh":{"bytes":15609,"sha256":"5776c70ee3b11d0d60ca96daa0bfb77a3dd2e1a6c9d934939d207e5da31001c8"},"slurm-223532.stdout":{"bytes":4735,"sha256":"6dd491359bd074cc714bc2a01317c413a011493ed88067d88c8644c57a4764e3"},"slurm-223532.stderr":{"bytes":2114,"sha256":"4efc4169574534322422c18008aadf82b813ae75ebb8b3127313c23309a0dca3"},"history_binding_pytest.stdout":{"bytes":0,"sha256":"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"},"history_binding_pytest.stderr":{"bytes":2114,"sha256":"4efc4169574534322422c18008aadf82b813ae75ebb8b3127313c23309a0dca3"},"test_support/test_support_manifest.json":{"bytes":18958,"sha256":"59c91069fae4a880e559546c0c370b9fbedbd1ee716b6731ac28cd6b75f79d41"},"gate_04105700.stdout":{"bytes":866,"sha256":"9f684ee9b86c6903cb7c42ae7bfdde643ceaa01cdb76ccdca4ac0a90897fa6e6"},"gate_04105700.stderr":{"bytes":0,"sha256":"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"},"gate_08070200.stdout":{"bytes":869,"sha256":"ac6605fd9450a82ae11c16339faeb7d0521631c1f10c025c6ee8354c35e52591"},"gate_08070200.stderr":{"bytes":0,"sha256":"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"},"gate_09035800.stdout":{"bytes":868,"sha256":"dac90bcb54fd64af967e7894252eaad29dc2ed4a90015ea755b273ea6a68360b"},"gate_09035800.stderr":{"bytes":0,"sha256":"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}}
old_smb=(old_runtime/'test_support/test_support_manifest.json').read_bytes()
require(sha(old_smb)=='59c91069fae4a880e559546c0c370b9fbedbd1ee716b6731ac28cd6b75f79d41','failed runtime support manifest changed')
old_sm=json.loads(old_smb)
expected_old_runtime=set(old_runtime_texts)|{'isolated_pytest_support.tar.gz'}|{'test_support/'+n for n in old_sm['member_sha256']}
actual_old_runtime={p.relative_to(old_runtime).as_posix():p for p in old_runtime.rglob('*') if p.is_file()}
require(set(actual_old_runtime)==expected_old_runtime,'failed runtime file set changed')
for name,item in old_runtime_texts.items():
    p=actual_old_runtime[name];data=p.read_bytes()
    require(not p.is_symlink() and len(data)==item['bytes'] and sha(data)==item['sha256'],'failed runtime text changed: '+name)
for name,h in old_sm['member_sha256'].items():
    p=actual_old_runtime['test_support/'+name];require(not p.is_symlink() and sha(p.read_bytes())==h,'failed test support changed')
old_archive=(old_runtime/'isolated_pytest_support.tar.gz').read_bytes()
require(len(old_archive)==397296 and sha(old_archive)=='e485003651d55dac384f69cd11819300375fecb7ef0a2fe406c3857c0dc8d954','failed runtime archive changed')
require(not (old_runtime/'history_binding_junit.xml').exists() and not (old_runtime/'synthetic_tmp').exists(),'failed runtime was retried or repaired in place')
print(json.dumps({'status':'OLD_RUNTIME_223532_FAILURE_PRESERVED','frozen_text_files':14,'all_files':len(actual_old_runtime),'original_test_support_files':135,'synthetic_tests_started_in_old_job':0,'synthetic_toy_updates_actual_in_old_job':0}),flush=True)

os.umask(0o077)
queue = run(['squeue','-h','-u',str(os.getuid()),'-o','%i|%200j|%T|%N'])
emit('CURRENT_USER_QUEUE',queue)
require(queue.returncode==0,'queue query failed')
related=[line for line in queue.stdout.decode().splitlines() if re.search(r'kdpp|DAILY_CAMELS_KNET_PER_BASIN|daily.camels.*per.basin|kalmannet.daily.perbasin',line,re.I)]
require(not related,'related active job exists; do not submit')
node=run(['scontrol','-d','show','node','ngu203'])
emit('EXACT_TARGET_NODE',node)
require(node.returncode==0,'node query failed')
node_fields=dict(item.split('=',1) for item in node.stdout.decode().split() if '=' in item)
require(node_fields.get('NodeName')=='ngu203' and node_fields.get('State') in {'IDLE','MIXED'} and node_fields.get('Partitions')=='hgpu8','target must permit normal allocation in hgpu8')
require(int(node_fields['CPUTot'])-int(node_fields['CPUAlloc'])>=4,'fewer than four currently unallocated CPUs')
gpu_cfg=re.fullmatch(r'gpu:(\d+)(?:\(.*\))?',node_fields.get('Gres',''))
gpu_used=re.match(r'gpu:(\d+)(?:\(|,|$)',node_fields.get('GresUsed',''))
require(gpu_cfg is not None and gpu_used is not None,'GPU allocation cannot be read')
require(int(gpu_cfg.group(1))-int(gpu_used.group(1))>=1,'no unallocated GPU at pre-submit read')
print(json.dumps({'resource_rule':'one normally allocated GPU and four CPUs; MIXED permitted','GPUCount':int(gpu_cfg.group(1)),'GPUAllocated':int(gpu_used.group(1)),'other_jobs_modified':0}),flush=True)
partition=run(['scontrol','show','partition','hgpu8'])
emit('EXACT_PARTITION',partition)
require(partition.returncode==0,'partition query failed')
pf=dict(item.split('=',1) for item in partition.stdout.decode().split() if '=' in item)
require(pf.get('State')=='UP' and pf.get('PreemptMode')=='OFF' and pf.get('OverSubscribe')=='NO' and pf.get('QoS')=='N/A','partition isolation differs')
scheduler=run(['scontrol','show','config'])
require(scheduler.returncode==0,'scheduler settings unavailable')
sf={k.strip():v.strip() for line in scheduler.stdout.decode().splitlines() if '=' in line for k,v in [line.split('=',1)]}
require(sf.get('PreemptType')=='preempt/none' and sf.get('PreemptMode')=='OFF','global preemption must be disabled')
print(json.dumps({'PreemptType':sf['PreemptType'],'PreemptMode':sf['PreemptMode'],'PrivateData':sf.get('PrivateData')},sort_keys=True),flush=True)
reservations=run(['scontrol','-o','show','reservation'])
require(reservations.returncode==0,'reservation inventory unavailable')
conflicting=[]
for line in reservations.stdout.decode().splitlines():
    if 'ReservationName=' not in line: continue
    fields=dict(item.split('=',1) for item in line.split() if '=' in item)
    nodes=fields.get('Nodes','')
    if not nodes or nodes in {'(null)','NONE'}: continue
    expanded=run(['scontrol','show','hostnames',nodes])
    require(expanded.returncode==0,'reservation host expansion failed')
    if 'ngu203' in expanded.stdout.decode().splitlines(): conflicting.append(line)
require(not conflicting,'target has a reservation; do not request its resources')
locks=root/'status/locks'
require(not locks.is_symlink() and (not locks.exists() or not list(locks.iterdir())),'existing execution lock or linked parent')
runs=root/'runs'
require(runs.is_dir() and not runs.is_symlink(),'run parent differs')

def verify_old_runtime223573():
    previous=pathlib.Path('/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901/node_recovery_20260907/historyfix1_runtime_recovery1_seq51')
    require(previous.is_dir() and previous.resolve()==previous and not previous.is_symlink(),'previous runtime parent differs')
    texts={"pre_submit_baseline.json":{"bytes":1997,"sha256":"236c5f07329411427d0de7f8b7c552567a5bdb890b31b089318c0376d8e4aae3"},"submission_receipt.json":{"bytes":368,"sha256":"ec50f0d003cffe46c6a8421164e912769e5804fadee3208e15a3f17b11ba8e96"},"runtime_gate.sh":{"bytes":19342,"sha256":"329a9de595b1184df2051b36106fe4657f0099b2264618734c8a1906ccf7c580"},"resource_bind.py":{"bytes":10831,"sha256":"417103ee5970a152d4c2eb3bdac36fd928817b7a28c099148b481acd4a66070a"},"slurm-223573.stdout":{"bytes":10933,"sha256":"e7c62ff38338bc8bbbbea7220878f4f51b75027d385aa3f5c3cb221d2e013deb"},"slurm-223573.stderr":{"bytes":1035,"sha256":"a1cb007e9858af833adc6804e434fecb11a8db40bbaa0123520710240925f8e7"},"test_support/test_support_manifest.json":{"bytes":19284,"sha256":"a3d2a9cdff2a5b2f507afd4426e60297495c3bd417f2129620a082239a44804c"}}
    for name, expected in texts.items():
        p=previous/name
        require(p.is_file() and not p.is_symlink(),'previous runtime text missing or linked')
        data=p.read_bytes()
        require(len(data)==expected['bytes'] and sha(data)==expected['sha256'],'previous runtime text changed: '+name)
    sm=json.loads((previous/'test_support/test_support_manifest.json').read_bytes())
    actual={p.relative_to(previous).as_posix():p for p in previous.rglob('*') if p.is_file()}
    expected_names=set(texts)|{'isolated_pytest_support.tar.gz'}|{'test_support/'+n for n in sm['member_sha256']}
    require(set(actual)==expected_names,'previous runtime namespace changed')
    for name,h in sm['member_sha256'].items():
        p=actual['test_support/'+name]
        require(not p.is_symlink() and sha(p.read_bytes())==h,'previous runtime support changed')
    archive=actual['isolated_pytest_support.tar.gz']
    require(not archive.is_symlink() and sha(archive.read_bytes())=='4d96b1169a5ab9aa654125fc339f78baeb6f815089313889f8ffdf5829f8b034','previous runtime archive changed')
    ledger=previous.parent/'historyfix1_runtime_recovery_once.json'
    require(ledger.is_file() and not ledger.is_symlink() and sha(ledger.read_bytes())=='d8a743a372fdab2643f2c19a343da0ac9d76599bdafc5ca8b01bbfeae8e3da26','used original engineering ledger changed')
    for name in ('output_parent','tmp','cache'):
        p=previous/name
        require(p.is_dir() and not p.is_symlink() and not list(p.iterdir()),'previous empty directory changed')
    require(not (previous/'synthetic_tmp').exists(),'previous synthetic tests unexpectedly started')
    print(json.dumps({'status':'OLD_RUNTIME_223573_FAILURE_AND_USED_ENGINEERING_LEDGER_PRESERVED','old_runtime_files':len(actual),'scientific_updates':0,'synthetic_updates':0}),flush=True)
verify_old_runtime223573()

before_runs=sorted(p.name for p in runs.iterdir())
expected_v1=sorted(expected_runs+[completed_first_run,completed_second_run])
require(before_runs==expected_v1,'run namespace changed; refuse to collide with existing work')
first_run=runs/completed_first_run
first_terminal_files={
    'preflight.json':'8293176a175f4ac00ead9520dd7e7ee2107c500128e98cfa57b2e1547e7c3e63',
    'epoch_history.json':'d41aa2901be8b434bd18fffdb462bbf3f4ec34b3dd5aad87925b4358a3644a33',
    'result_summary.json':'2f93e42dbac6f6ef3017ca01302987d9195eda292573fd547eef7b52aada8a34',
    'completion.marker.json':'6171e34dd65753326bab4b526fae18bfd78022bd66c3df69b3905d6bc02eaed0',
    'manifest.sha256.json':'3c43638ec5dc9313e60e5037ff08bc79765a3251df5b3ce1137405c71369295c'}
require(first_run.is_dir() and first_run.resolve()==first_run and not first_run.is_symlink(),'completed first run missing or linked')
for name,expected in first_terminal_files.items():
    p=first_run/name
    require(p.is_file() and not p.is_symlink() and sha(p.read_bytes())==expected,'completed first-run evidence differs: '+name)
first_audit=root/'status'/(completed_first_run+'.audit.json')
require(first_audit.is_file() and not first_audit.is_symlink() and sha(first_audit.read_bytes())=='293e0476d2f8f01a8a2a0580c022fa5e225e8047cd8d4b3155c72c53959e10da','completed first-run audit differs')
first_stderr=root/'status'/(completed_first_run+'.slurm-223629.stderr')
require(first_stderr.is_file() and not first_stderr.is_symlink() and sha(first_stderr.read_bytes())=='e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855','completed first-run stderr differs')
first_summary=json.loads((first_run/'result_summary.json').read_text())
first_completion=json.loads((first_run/'completion.marker.json').read_text())
first_verification=json.loads(first_audit.read_text())
for item in (first_summary,first_completion,first_verification):
    require(item['execution_id']==completed_first_run and item['basin_id']=='04105700' and item['terminal_state']=='COMPLETED','completed first-run terminal identity differs')
    require(item['completed_epoch']==80 and item['optimizer_steps']==80 and item['technical_success'] is True and item['formal_evaluation_access_count']==0,'completed first-run gate differs')
require(first_summary['scientific_capability_passed'] is True and first_completion['scientific_capability_passed'] is True and first_verification['verification_passed'] is True,'completed first-run independent gate not satisfied')
first_accounting=run(['sacct','-n','-P','-j','223629','--format=JobID,State,ExitCode,NodeList'])
emit('COMPLETED_FIRST_BASIN_ACCOUNTING',first_accounting)
require(first_accounting.returncode==0,'first-basin accounting query failed')
first_rows=[line.split('|') for line in first_accounting.stdout.decode().splitlines() if line.startswith('223629|')]
require(len(first_rows)==1 and first_rows[0][:4]==['223629','COMPLETED','0:0','ngu201'],'first-basin scheduler terminal state differs')
print(json.dumps({'status':'FIRST_BASIN_TERMINAL_AND_INDEPENDENT_ACCEPTANCE_BOUND','execution_id':completed_first_run,'independent_acceptance_sha256':'da36ce54be233d80b782fc91b03ad3b17a15cb5f04062777730b2b98d2de544d','checkpoint_downloads':0,'formal_evaluation_access_count':0}),flush=True)
second_run=runs/completed_second_run
second_terminal_files={
    'preflight.json':'840e8b8920536dab8540e664ab4ee59bf235cd7ac2548738d116aeb2b9d699c3',
    'epoch_history.json':'ecfb23072d3f7dd549a0361e62267dc6de5f4dac4d08315eec892a2ae16f05b7',
    'result_summary.json':'f167243c3a1a201bd08680665b6b0c18892f6d992ee4886c70668fc6a497800b',
    'completion.marker.json':'ed94301198f429234752b1e3c5426a250ff7019d9c258e94ef8ecab070566826',
    'manifest.sha256.json':'e43d09bbba2d7178fceb213e967eb27685a42ebdee0158aa769eb65abdd2f283'}
require(second_run.is_dir() and second_run.resolve()==second_run and not second_run.is_symlink(),'completed second run missing or linked')
for name,expected in second_terminal_files.items():
    p=second_run/name
    require(p.is_file() and not p.is_symlink() and sha(p.read_bytes())==expected,'completed second-run evidence differs: '+name)
second_audit=root/'status'/(completed_second_run+'.audit.json')
require(second_audit.is_file() and not second_audit.is_symlink() and sha(second_audit.read_bytes())=='55136aa929c8a06ed6ab37eee306f8fb02949e68e157390ddb76fdfedc230b1a','completed second-run audit differs')
second_stderr=root/'status'/(completed_second_run+'.slurm-223689.stderr')
require(second_stderr.is_file() and not second_stderr.is_symlink() and sha(second_stderr.read_bytes())=='e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855','completed second-run stderr differs')
second_summary=json.loads((second_run/'result_summary.json').read_text())
second_completion=json.loads((second_run/'completion.marker.json').read_text())
second_verification=json.loads(second_audit.read_text())
for item in (second_summary,second_completion,second_verification):
    require(item['execution_id']==completed_second_run and item['basin_id']=='08070200' and item['terminal_state']=='COMPLETED','completed second-run terminal identity differs')
    require(item['completed_epoch']==80 and item['optimizer_steps']==80 and item['technical_success'] is True and item['formal_evaluation_access_count']==0,'completed second-run technical gate differs')
require(second_summary['scientific_capability_passed'] is False and second_completion['scientific_capability_passed'] is False,'completed second-run science failure was rewritten')
require(second_summary['relative_accuracy_status']=='KALMANNET_ADVANTAGE' and second_completion['relative_accuracy_status']=='KALMANNET_ADVANTAGE','completed second-run relative accuracy differs')
require(second_verification['verification_passed'] is True and second_verification['scientific_capability_passed'] is False,'completed second-run independent remote verification differs')
second_accounting=run(['sacct','-n','-P','-j','223689','--format=JobID,State,ExitCode,NodeList'])
emit('COMPLETED_SECOND_BASIN_ACCOUNTING',second_accounting)
require(second_accounting.returncode==0,'second-basin accounting query failed')
second_rows=[line.split('|') for line in second_accounting.stdout.decode().splitlines() if line.startswith('223689|')]
require(len(second_rows)==1 and second_rows[0][:4]==['223689','COMPLETED','0:0','ngu203'],'second-basin scheduler terminal state differs')
print(json.dumps({'status':'SECOND_BASIN_TERMINAL_AND_INDEPENDENT_ACCEPTANCE_BOUND','execution_id':completed_second_run,'scientific_capability_status':'FAILED','relative_accuracy_status':'KALMANNET_ADVANTAGE','independent_acceptance_sha256':'5e83a39b81912d3fa0fec9fa34a25301f98b12be7e28fb0c1c125af97f70e80a','checkpoint_downloads':0,'formal_evaluation_access_count':0}),flush=True)
runtime_audit=root/'node_recovery_20260907/historyfix1_runtime_attempt3_seq53'
require(runtime_audit.is_dir() and runtime_audit.resolve()==runtime_audit,'accepted runtime audit path differs')
accepted_runtime_files={"gate_04105700.stderr":{"bytes":0,"sha256":"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"},"gate_04105700.stdout":{"bytes":866,"sha256":"785b2bb4eb01b6b2bde465123e4e752fe20d78c6ca7406f98a875e6ca94f099f"},"gate_08070200.stderr":{"bytes":0,"sha256":"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"},"gate_08070200.stdout":{"bytes":869,"sha256":"30ddb7090c1cef673105dfedbb3d426c5c0c23317feb1b78fb7eacafae691b64"},"gate_09035800.stderr":{"bytes":0,"sha256":"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"},"gate_09035800.stdout":{"bytes":868,"sha256":"122419cfa1462a3eef4634fbf9aaf5e475d3e2511513360042aa483d150cc76f"},"history_binding_junit.xml":{"bytes":5387,"sha256":"70921cba1e97fcb73d7b6a34a69f21338aa128770d4dba956f47a31ced6caac3"},"history_binding_pytest.stderr":{"bytes":0,"sha256":"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"},"history_binding_pytest.stdout":{"bytes":1823,"sha256":"f6e416ec99358785d6c7b64f9dd4f7abe7ae6246899610dde39be6a413b949ff"},"pre_submit_baseline.json":{"bytes":2025,"sha256":"813d3287e02463851712ae44f66a7981b468a99510fbad4b9e2afcab6b38d48d"},"resource_bind.py":{"bytes":16968,"sha256":"6d67fe1b965c6af590f2cdc08a49a1d817a2d0e656926c03d76837ff4315c96b"},"runtime_gate.sh":{"bytes":22339,"sha256":"8909b749e16cbc7d4a9610f2f1d87b844f2052f663d2cc0579c7b1a2a0a02d08"},"slurm-223590.stderr":{"bytes":137,"sha256":"61b12692da340e5bd3a9adea860752fa8f6c439a6c1354bd2a7156ec7c1aa9a8"},"slurm-223590.stdout":{"bytes":156333,"sha256":"0d74b9756e2eac5e9538aef72ee47c6114817d02eae1313b277d89d7d8a676ae"},"submission_receipt.json":{"bytes":368,"sha256":"77ca770a65b15d0ceb24dee3a5aa7345ced539434fb0335619368fcca75740c9"},"test_support/test_support_manifest.json":{"bytes":19284,"sha256":"a3d2a9cdff2a5b2f507afd4426e60297495c3bd417f2129620a082239a44804c"}}
for name,item in accepted_runtime_files.items():
    p=runtime_audit/name
    require(p.is_file() and not p.is_symlink(),'accepted runtime evidence missing or linked: '+name)
    b=p.read_bytes()
    require(len(b)==item['bytes'] and sha(b)==item['sha256'],'accepted runtime evidence differs: '+name)
require(not any((runtime_audit/'output_parent').iterdir()),'accepted runtime output parent changed')
prior=run(['sacct','-n','-P','-j','223590','--format=JobID,State,ExitCode,NodeList'])
emit('ACCEPTED_RUNTIME_ACCOUNTING',prior)
require(prior.returncode==0,'runtime accounting query failed')
prior_rows=[line.split('|') for line in prior.stdout.decode().splitlines() if line.startswith('223590|')]
require(len(prior_rows)==1 and prior_rows[0][:4]==['223590','FAILED','1:0','ngu201'],'runtime terminal state differs')
qualification_bytes="{\"accepted_runtime_files\": {\"gate_04105700.stderr\": {\"bytes\": 0, \"sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"}, \"gate_04105700.stdout\": {\"bytes\": 866, \"sha256\": \"785b2bb4eb01b6b2bde465123e4e752fe20d78c6ca7406f98a875e6ca94f099f\"}, \"gate_08070200.stderr\": {\"bytes\": 0, \"sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"}, \"gate_08070200.stdout\": {\"bytes\": 869, \"sha256\": \"30ddb7090c1cef673105dfedbb3d426c5c0c23317feb1b78fb7eacafae691b64\"}, \"gate_09035800.stderr\": {\"bytes\": 0, \"sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"}, \"gate_09035800.stdout\": {\"bytes\": 868, \"sha256\": \"122419cfa1462a3eef4634fbf9aaf5e475d3e2511513360042aa483d150cc76f\"}, \"history_binding_junit.xml\": {\"bytes\": 5387, \"sha256\": \"70921cba1e97fcb73d7b6a34a69f21338aa128770d4dba956f47a31ced6caac3\"}, \"history_binding_pytest.stderr\": {\"bytes\": 0, \"sha256\": \"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\"}, \"history_binding_pytest.stdout\": {\"bytes\": 1823, \"sha256\": \"f6e416ec99358785d6c7b64f9dd4f7abe7ae6246899610dde39be6a413b949ff\"}, \"pre_submit_baseline.json\": {\"bytes\": 2025, \"sha256\": \"813d3287e02463851712ae44f66a7981b468a99510fbad4b9e2afcab6b38d48d\"}, \"resource_bind.py\": {\"bytes\": 16968, \"sha256\": \"6d67fe1b965c6af590f2cdc08a49a1d817a2d0e656926c03d76837ff4315c96b\"}, \"runtime_gate.sh\": {\"bytes\": 22339, \"sha256\": \"8909b749e16cbc7d4a9610f2f1d87b844f2052f663d2cc0579c7b1a2a0a02d08\"}, \"slurm-223590.stderr\": {\"bytes\": 137, \"sha256\": \"61b12692da340e5bd3a9adea860752fa8f6c439a6c1354bd2a7156ec7c1aa9a8\"}, \"slurm-223590.stdout\": {\"bytes\": 156333, \"sha256\": \"0d74b9756e2eac5e9538aef72ee47c6114817d02eae1313b277d89d7d8a676ae\"}, \"submission_receipt.json\": {\"bytes\": 368, \"sha256\": \"77ca770a65b15d0ceb24dee3a5aa7345ced539434fb0335619368fcca75740c9\"}, \"test_support/test_support_manifest.json\": {\"bytes\": 19284, \"sha256\": \"a3d2a9cdff2a5b2f507afd4426e60297495c3bd417f2129620a082239a44804c\"}}, \"changed_runtime_artifacts\": 0, \"checkpoint_downloads\": 0, \"classified_residuals\": [], \"completed_cpu_toy_updates_asserted_by_registered_tests\": 405, \"formal_evaluation_access_count\": 0, \"gates\": [{\"basin_id\": \"04105700\", \"causal_future_observation_test\": true, \"checkpoint_restore_test\": true, \"correction_cap_enabled\": true, \"correction_cap_in_state_scale_units\": 3.0, \"device\": \"cuda\", \"divergence_stop_checkpoint_ratio\": 100.0, \"divergence_stop_post_step_ratio\": 100.0, \"epoch_zero_joint_resume_test\": true, \"exact_active_mask_no_padding\": true, \"experiment_family\": \"DAILY_CAMELS_KNET_PER_BASIN_PILOT_V2_20260902\", \"finite_nonzero_gradient_test\": true, \"formal_evaluation_access_count\": 0, \"gpu_name\": \"NVIDIA A800-SXM4-80GB\", \"optimizer_steps\": 0, \"schema_version\": \"daily_camels_knet_per_basin_runtime_gate_v2\", \"segment_objective\": 0.5124326818123652, \"segment_target_count_by_lead\": {\"1\": 102, \"2\": 102, \"3\": 102}, \"state_dimension\": 7, \"status\": \"PASS\", \"temporary_checkpoint_sha256\": \"134fbcd3fedbf0648785e5080a09a8b9214d038c43c10b73e330789a2bf0e009\"}, {\"basin_id\": \"08070200\", \"causal_future_observation_test\": true, \"checkpoint_restore_test\": true, \"correction_cap_enabled\": true, \"correction_cap_in_state_scale_units\": 3.0, \"device\": \"cuda\", \"divergence_stop_checkpoint_ratio\": 100.0, \"divergence_stop_post_step_ratio\": 100.0, \"epoch_zero_joint_resume_test\": true, \"exact_active_mask_no_padding\": true, \"experiment_family\": \"DAILY_CAMELS_KNET_PER_BASIN_PILOT_V2_20260902\", \"finite_nonzero_gradient_test\": true, \"formal_evaluation_access_count\": 0, \"gpu_name\": \"NVIDIA A800-SXM4-80GB\", \"optimizer_steps\": 0, \"schema_version\": \"daily_camels_knet_per_basin_runtime_gate_v2\", \"segment_objective\": 0.011580336754919346, \"segment_target_count_by_lead\": {\"1\": 102, \"2\": 102, \"3\": 102}, \"state_dimension\": 11, \"status\": \"PASS\", \"temporary_checkpoint_sha256\": \"a13ed22ccd45390320b88cbd444d240f615e91ed89c177324ad265ddfbe589b2\"}, {\"basin_id\": \"09035800\", \"causal_future_observation_test\": true, \"checkpoint_restore_test\": true, \"correction_cap_enabled\": true, \"correction_cap_in_state_scale_units\": 3.0, \"device\": \"cuda\", \"divergence_stop_checkpoint_ratio\": 100.0, \"divergence_stop_post_step_ratio\": 100.0, \"epoch_zero_joint_resume_test\": true, \"exact_active_mask_no_padding\": true, \"experiment_family\": \"DAILY_CAMELS_KNET_PER_BASIN_PILOT_V2_20260902\", \"finite_nonzero_gradient_test\": true, \"formal_evaluation_access_count\": 0, \"gpu_name\": \"NVIDIA A800-SXM4-80GB\", \"optimizer_steps\": 0, \"schema_version\": \"daily_camels_knet_per_basin_runtime_gate_v2\", \"segment_objective\": 0.02303260138699481, \"segment_target_count_by_lead\": {\"1\": 102, \"2\": 102, \"3\": 102}, \"state_dimension\": 18, \"status\": \"PASS\", \"temporary_checkpoint_sha256\": \"dd25347360dc42aa6dba946ee8d6c690f19ca3ee9831aec30134473ca57b474c\"}], \"no_cleanup_or_runtime_artifact_modification_performed\": true, \"original_accounting\": [[\"223590\", \"kdpp-v2-historyfix1-runtime-attempt3-53\", \"FAILED\", \"1:0\", \"00:06:29\", \"ngu201\", \"4\", \"4\"]], \"original_empty_directory_postcondition_revalidated\": true, \"original_failure_phase\": \"ORIGINAL_POST_TEST_EMPTY_DIRECTORY_CHECK_FAILED\", \"original_failure_preserved\": true, \"original_numeric_runtime_optimizer_updates\": 0, \"original_runtime_exit_code\": \"1:0\", \"original_runtime_job_id\": \"223590\", \"original_runtime_job_state\": \"FAILED\", \"recomputed_numeric_checks\": 0, \"rerun_synthetic_tests\": 0, \"resources\": {\"cpu_affinity\": [10, 11, 42, 43], \"gpu_uuid\": \"GPU-9a549ddb-00b0-58aa-7b63-01955b652044\", \"status\": \"ACTUAL_ASSIGNED_GPU_AND_CPU_PASS\"}, \"result55_sha256\": \"2deac457fe483af6e0abaf399e37aec305354616a4899ff491e753cdda9d6dd4\", \"result56_sha256\": \"4bc816b95f33b89b6f996575ac29d5faf59b11bb8f79f2940afe936a6d87c9de\", \"schema_version\": \"historyfix1_readonly_runtime_qualification_v1\", \"scientific_success_not_claimed\": true, \"scientific_training_updates\": 0, \"source_of_authority\": \"execution-semantics-addendum section8 line422 and section10 line525\", \"status\": \"TECHNICAL_RUNTIME_PREREQUISITES_PASS_VIA_READONLY_POSTCHECK_REPAIR\", \"test_count\": 29, \"transient_contents_at_original_failure\": \"UNKNOWN_NOT_RECONSTRUCTED\", \"verifier_sha256\": \"da3970ab041bfe9e69b7e6c086a108ae70c3a500ecdce8eec0d653eebe2f91e4\"}\n".encode('utf-8')
require(sha(qualification_bytes)=='4615b06aaf8c9e323ad5695ee321e8e3dc52e1ae35e1692b252b528f4d7f9c19','new readonly qualification bytes differ')
qualification=json.loads(qualification_bytes)
require(qualification['status']=='TECHNICAL_RUNTIME_PREREQUISITES_PASS_VIA_READONLY_POSTCHECK_REPAIR','new readonly qualification missing')
require(qualification['original_runtime_job_id']=='223590' and qualification['original_runtime_job_state']=='FAILED' and qualification['original_runtime_exit_code']=='1:0','do not rewrite original failure')
require(qualification['verifier_sha256']=='da3970ab041bfe9e69b7e6c086a108ae70c3a500ecdce8eec0d653eebe2f91e4','qualified reading tool identity differs')
require(qualification['result56_sha256']=='4bc816b95f33b89b6f996575ac29d5faf59b11bb8f79f2940afe936a6d87c9de','postcheck authority differs')
require(qualification['accepted_runtime_files']==accepted_runtime_files,'qualified terminal fingerprints differ')
require(qualification['original_failure_preserved'] and qualification['original_empty_directory_postcondition_revalidated'],'failure/revalidation scope missing')
for folder in ('output_parent','tmp','cache'):
    p=runtime_audit/folder
    require(p.is_dir() and not p.is_symlink() and p.resolve()==p and not list(p.iterdir()),'original empty-directory postcondition not currently satisfied')
runtime_support=runtime_audit/'test_support'
sm=json.loads((runtime_support/'test_support_manifest.json').read_bytes())
sf={p.relative_to(runtime_support).as_posix():p for p in runtime_support.rglob('*') if p.is_file()}
require(set(sf)==set(sm['member_sha256'])|{'test_support_manifest.json'},'qualified support inventory differs')
for name,h in sm['member_sha256'].items():
    require(not sf[name].is_symlink() and sha(sf[name].read_bytes())==h,'qualified support member changed')
require(sha((runtime_audit/'isolated_pytest_support.tar.gz').read_bytes())=='4d96b1169a5ab9aa654125fc339f78baeb6f815089313889f8ffdf5829f8b034','qualified support archive changed')
ledger=runtime_audit.parent/'historyfix1_runtime_attempt3_seq53.json'
require(not ledger.is_symlink() and sha(ledger.read_bytes())=='5e54e01e9a249a58593d25bbae89e7ae3f9d3f15e2f79966a575e6ee63f1d2b3','runtime ledger changed')
print(json.dumps({'status':'READONLY_QUALIFIED_PREREQUISITES_RECHECKED','original_runtime_job_id':'223590','original_runtime_job_state':'FAILED','qualification_sha256':sha(qualification_bytes),'runtime_file_hashes_rechecked':len(accepted_runtime_files),'all_original_empty_directory_postconditions':True,'new_scientific_training_not_yet_submitted':True}),flush=True)

experiment_id='DAILY_CAMELS_KNET_PER_BASIN_PILOT_09035800_V2_20260902_A45'
execution_id='DAILY_CAMELS_KNET_PER_BASIN_PILOT_09035800_V2_20260902_A45_HISTORYFIX1_A800_TRAIN1_SEQ66'
config_rel='configs/daily_camels_knet_per_basin_pilot_v2_09035800.json'
config_bytes=(source/config_rel).read_bytes()
require(sha(config_bytes)==m['member_sha256'][config_rel],'sealed third configuration differs')
configuration=json.loads(config_bytes)
require(configuration['experiment_id']==experiment_id and configuration['basin_id']=='09035800' and configuration['model']['state_dimension']==18,'third basin identity differs')
require(len(configuration['source_sha256'])==18 and configuration['formal_evaluation_enabled'] is False,'third configuration policy differs')
sealed_script=source/'hpc/daily_camels_knet_per_basin/submit_train_gpu.slurm'
require(sha(sealed_script.read_bytes())=='f7ed33fd12a3db262f5d7f9b730fd841cd9de2f2a21d021536855f5602689bcf','sealed training launcher differs')
status=root/'status'
for parent in [status,status/'tmp',status/'cache',status/'locks',root/'node_recovery_20260907']:
    require(parent.is_dir() and parent.resolve()==parent and not parent.is_symlink(),'registered parent missing or linked: '+str(parent))
run_directory=runs/execution_id
audit_report=status/(execution_id+'.audit.json')
require(not run_directory.exists() and not run_directory.is_symlink(),'training run already exists')
require(not list(status.glob(execution_id+'*')),'training status evidence name already exists')
require(not (locks/(execution_id+'.lock')).exists(),'training owner lock already exists')
launch=root/'node_recovery_20260907/train_09035800_historyfix1_seq66'
require(launch.resolve()==launch and not launch.exists() and not launch.is_symlink(),'training launch directory already exists; do not submit again')
launch.mkdir()
for name in ['tmp','cache']: (launch/name).mkdir()
script = "#!/usr/bin/env bash\n#SBATCH --job-name=kdpp-v2-train-09035800-historyfix1_seq66\n#SBATCH --partition=hgpu8\n#SBATCH --nodelist=ngu203\n#SBATCH --nodes=1\n#SBATCH --ntasks=1\n#SBATCH --cpus-per-task=4\n#SBATCH --gres=gpu:1\n#SBATCH --time=12:00:00\n#SBATCH --no-requeue\n#SBATCH --chdir=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901/deployments/DAILY_CAMELS_KNET_PER_BASIN_V2_BUNDLE_HISTORYFIX1_DEPLOY_SEQ43/source\n#SBATCH --output=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901/status/DAILY_CAMELS_KNET_PER_BASIN_PILOT_09035800_V2_20260902_A45_HISTORYFIX1_A800_TRAIN1_SEQ66.slurm-%j.stdout\n#SBATCH --error=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901/status/DAILY_CAMELS_KNET_PER_BASIN_PILOT_09035800_V2_20260902_A45_HISTORYFIX1_A800_TRAIN1_SEQ66.slurm-%j.stderr\nset -eo pipefail\numask 077\n[[ \"${SLURM_RESTART_COUNT:-0}\" == 0 ]] || exit 82\n[[ -n \"${SLURM_JOB_ID:-}\" && \"$(hostname -s)\" == ngu203 ]] || exit 81\n[[ \"${SLURM_CPUS_PER_TASK:-}\" == 4 && -n \"${CUDA_VISIBLE_DEVICES:-}\" ]] || exit 83\nSOURCE=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901/deployments/DAILY_CAMELS_KNET_PER_BASIN_V2_BUNDLE_HISTORYFIX1_DEPLOY_SEQ43/source\nAUDIT=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901/node_recovery_20260907/train_09035800_historyfix1_seq66\nROOT=/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901\nPY=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python\n[[ \"${SLURM_SUBMIT_DIR:-}\" == \"$SOURCE\" ]] || exit 84\n[[ ! -e \"$ROOT/status/tmp/$SLURM_JOB_ID\" && ! -L \"$ROOT/status/tmp/$SLURM_JOB_ID\" ]] || exit 85\n[[ ! -e \"$ROOT/status/cache/$SLURM_JOB_ID\" && ! -L \"$ROOT/status/cache/$SLURM_JOB_ID\" ]] || exit 86\nexport PYTHONDONTWRITEBYTECODE=1 PYTHONOPTIMIZE=0 CUDA_CACHE_DISABLE=1\nexport OMP_NUM_THREADS=4 MKL_NUM_THREADS=4 OPENBLAS_NUM_THREADS=4 NUMEXPR_NUM_THREADS=4\nexport MKL_THREADING_LAYER=GNU MKL_SERVICE_FORCE_INTEL=1\nexport TMPDIR=\"$AUDIT/tmp\" XDG_CACHE_HOME=\"$AUDIT/cache\"\nexport PYTHONPATH=\"$SOURCE/src:$SOURCE\"\nexport PILOT_REMOTE_ROOT=\"$ROOT\"\nexport PILOT_CONFIG_RELATIVE=configs/daily_camels_knet_per_basin_pilot_v2_09035800.json\nexport PILOT_EXECUTION_ID=DAILY_CAMELS_KNET_PER_BASIN_PILOT_09035800_V2_20260902_A45_HISTORYFIX1_A800_TRAIN1_SEQ66\nexport PILOT_AUDIT_REPORT=\"$ROOT/status/$PILOT_EXECUTION_ID.audit.json\"\ncd \"$SOURCE\"\nif [[ \"${1:-}\" != --resource-bound ]]; then\n    exec \"$PY\" -B \"$AUDIT/resource_bind.py\" \"$AUDIT/train.sh\"\nfi\nprintf 'slurm_job_id=%s hostname=%s CUDA_VISIBLE_DEVICES=%s execution_id=%s\\n' \"$SLURM_JOB_ID\" \"$(hostname -s)\" \"${CUDA_VISIBLE_DEVICES:-}\" \"$PILOT_EXECUTION_ID\"\ndate --iso-8601=seconds\n\"$PY\" -B -u - <<'RESOURCE_GATE'\nimport csv,io,json,os,pathlib,subprocess,sys\nexpected_cpu={int(x) for x in os.environ['KDPP_ALLOCATED_CPU_IDS'].split(',')}\nif set(os.sched_getaffinity(0)) != expected_cpu: raise RuntimeError('CPU affinity not inherited')\nif os.environ['CUDA_VISIBLE_DEVICES'] != os.environ['KDPP_ALLOCATED_GPU_UUID']: raise RuntimeError('GPU UUID mask not inherited')\nimport numpy, torch\ninfo=dict(stage='allocated_device_identity',python=sys.version.split()[0],numpy=numpy.__version__,torch=torch.__version__,cuda_available=torch.cuda.is_available(),visible_cuda_devices=torch.cuda.device_count())\nif not info['cuda_available'] or info['visible_cuda_devices'] != 1:\n    print(json.dumps(info),flush=True)\n    raise RuntimeError('exactly one allocated visible CUDA device required')\ninfo['gpu_name']=torch.cuda.get_device_name(0)\ninfo['gpu_free_bytes'],info['gpu_total_bytes']=torch.cuda.mem_get_info()\nprint(json.dumps(info),flush=True)\nif info['python']!='3.11.13' or info['numpy']!='2.3.3' or info['torch'].split('+')[0]!='2.4.0' or info['gpu_name']!='NVIDIA A800-SXM4-80GB':\n    raise RuntimeError('registered device or interpreter mismatch')\nif info['gpu_free_bytes']<64*1024**3:\n    raise RuntimeError('less than 64 GiB free on allocated A800; no experiment launched')\nr=subprocess.run(['nvidia-smi','--query-compute-apps=gpu_uuid,pid,used_gpu_memory','--format=csv,noheader,nounits'],capture_output=True,text=True,timeout=30,check=False)\nprint(json.dumps(dict(stage='actual_cuda_process_uuid',pid=os.getpid(),exit_code=r.returncode,stdout=r.stdout,stderr=r.stderr)),flush=True)\nif r.returncode != 0: raise RuntimeError('actual CUDA process mapping query failed')\nrows=[[x.strip() for x in row] for row in csv.reader(io.StringIO(r.stdout)) if row]\nif not all(len(row)==3 and row[1].isdigit() for row in rows): raise RuntimeError('unrecognized process mapping')\nown=[row for row in rows if row[1]==str(os.getpid())]\nif len(own)!=1 or own[0][0]!=os.environ['KDPP_ALLOCATED_GPU_UUID']: raise RuntimeError('actual CUDA process differs from allocated UUID')\nprint(json.dumps({'status':'ACTUAL_ASSIGNED_GPU_AND_CPU_PASS','gpu_uuid':own[0][0],'cpu_affinity':sorted(os.sched_getaffinity(0))}),flush=True)\nRESOURCE_GATE\necho 'SEALED_TRAINING_WRAPPER_BEGIN basin=09035800 requested_epochs=80'\nexec bash \"$SOURCE/hpc/daily_camels_knet_per_basin/submit_train_gpu.slurm\"\n"
binding_script="\"\"\"Bind this job's CPU set and allocated A800 before launching the frozen runtime gate.\"\"\"\nimport csv\nimport hashlib\nimport xml.etree.ElementTree as ET\nimport io\nimport json\nimport os\nimport pathlib\nimport re\nimport socket\nimport subprocess\nimport sys\n\ndef require(ok, message):\n    if not ok:\n        raise RuntimeError(message)\n\ndef parse_ids(value):\n    require(bool(re.fullmatch(r\"\\d+(?:-\\d+)?(?:,\\d+(?:-\\d+)?)*\", value)), \"invalid allocated CPU IDs\")\n    ids = []\n    for part in value.split(\",\"):\n        bounds = [int(x) for x in part.split(\"-\")]\n        require(len(bounds) == 1 or bounds[0] <= bounds[1], \"reversed CPU range\")\n        ids.extend(range(bounds[0], bounds[-1] + 1))\n    require(len(ids) == len(set(ids)), \"duplicate CPU IDs\")\n    return set(ids)\n\ndef parse_allocation(text, job_id, uid, env_gpu):\n    fields = dict(item.split(\"=\", 1) for item in text.split() if \"=\" in item)\n    require(fields.get(\"JobId\") == job_id and fields.get(\"JobState\") == \"RUNNING\", \"not this running job\")\n    require(fields.get(\"UserId\") == \"sunyiq(\" + str(uid) + \")\", \"wrong owner\")\n    require(fields.get(\"Partition\") == \"hgpu8\" and fields.get(\"NumNodes\") == \"1\", \"wrong allocation\")\n    require(fields.get(\"CPUs/Task\") == \"4\" and fields.get(\"NumTasks\") == \"1\", \"wrong task resources\")\n    matches = re.findall(r\"Nodes=(ngu203)\\s+CPU_IDs=([0-9,-]+)\\s+Mem=\\d+\\s+GRES=gpu\\(IDX:([0-9]+)\\)\", text)\n    require(len(matches) == 1, \"one detailed node allocation is required\")\n    node, cpus, gpu = matches[0]\n    require(gpu == env_gpu and re.fullmatch(r\"\\d+\", env_gpu), \"Slurm GPU identity disagrees\")\n    ids = parse_ids(cpus)\n    require(4 <= len(ids) <= int(fields[\"NumCPUs\"]), \"insufficient or excessive assigned CPUs\")\n    return node, ids, gpu\n\ndef select_gpu(text, gpu_uuid):\n    rows = [[x.strip() for x in row] for row in csv.reader(io.StringIO(text)) if row]\n    require(rows and all(len(row) == 6 for row in rows), \"unrecognized GPU inventory\")\n    require(len({row[0] for row in rows}) == len(rows), \"duplicate physical GPU index\")\n    selected = [row for row in rows if row[1] == gpu_uuid]\n    require(len(selected) == 1, \"allocated GPU absent from inventory\")\n    row = selected[0]\n    require(re.fullmatch(r\"GPU-[0-9a-fA-F-]+\", row[1]), \"invalid GPU UUID\")\n    require(row[2] == \"NVIDIA A800-SXM4-80GB\" and int(row[4]) >= 65536, \"allocated A800 memory unavailable\")\n    return row\n\n\ndef allocated_gpu_uuid(xml_text, gres_text, gpu):\n    devices = []\n    for line in gres_text.splitlines():\n        line = line.split(\"#\", 1)[0]\n        fields = dict(item.split(\"=\", 1) for item in line.split() if \"=\" in item)\n        if fields.get(\"NodeName\") == \"ngu203\" and fields.get(\"Name\") == \"gpu\":\n            devices.append(fields.get(\"File\"))\n    require(devices == [\"/dev/nvidia\" + str(i) for i in range(8)], \"registered GRES device order differs\")\n    require(gpu.isdigit() and 0 <= int(gpu) < len(devices), \"allocated GPU device index out of range\")\n    device = devices[int(gpu)]\n    minor = int(device.removeprefix(\"/dev/nvidia\"))\n    xml_gpus = list(ET.fromstring(xml_text).iter(\"gpu\"))\n    minors = [obj.findtext(\"minor_number\") for obj in xml_gpus]\n    require(all(x is not None and x.isdigit() for x in minors) and len(set(minors)) == len(minors), \"GPU XML minor identity missing or duplicate\")\n    selected = [obj for obj in xml_gpus if int(obj.findtext(\"minor_number\")) == minor]\n    require(len(selected) == 1, \"allocated device minor missing from GPU XML\")\n    uuid = selected[0].findtext(\"uuid\")\n    require(uuid is not None and re.fullmatch(r\"GPU-[0-9a-fA-F-]+\", uuid), \"GPU XML UUID missing\")\n    return device, minor, uuid\n\ndef compute_rows(text):\n    rows = [[x.strip() for x in row] for row in csv.reader(io.StringIO(text)) if row]\n    require(all(len(row) == 3 and row[1].isdigit() for row in rows), \"unrecognized compute process inventory\")\n    return rows\n\ndef captured(stage, args):\n    r = subprocess.run(args, capture_output=True, text=True, timeout=30, check=False)\n    print(json.dumps(dict(stage=stage, args=args, exit_code=r.returncode, stdout=r.stdout, stderr=r.stderr)), flush=True)\n    require(r.returncode == 0, stage + \" query failed\")\n    return r.stdout\n\n\ndef topology_cpu_map(xml_text, node_text):\n    tree = ET.fromstring(xml_text)\n    fields = dict(item.split(\"=\", 1) for item in node_text.split() if \"=\" in item)\n    cores = [obj for obj in tree.iter(\"object\") if obj.get(\"type\") == \"Core\"]\n    sockets = [obj for obj in tree.iter(\"object\") if obj.get(\"type\") in {\"Package\", \"Socket\"}]\n    numas = [obj for obj in tree.iter(\"object\") if obj.get(\"type\") in {\"NUMANode\", \"Node\"}]\n    threads = int(fields[\"ThreadsPerCore\"])\n    count = int(fields[\"CPUTot\"])\n    require(int(fields[\"Sockets\"]) in {len(sockets), len(numas)}, \"Slurm socket topology differs\")\n    require(len(cores) == int(fields[\"Sockets\"]) * int(fields[\"CoresPerSocket\"]), \"Slurm core topology differs\")\n    mapping = []\n    for core in cores:\n        pus = [obj for obj in core.iter(\"object\") if obj.get(\"type\") == \"PU\"]\n        require(len(pus) == threads, \"hwloc core thread count differs\")\n        mapping.extend(int(obj.attrib[\"os_index\"]) for obj in pus)\n    require(len(mapping) == len(set(mapping)) == count and set(mapping) == set(range(count)), \"non-bijective or unsupported CPU map\")\n    return mapping\n\ndef actual_slurmd_binary():\n    registered = pathlib.Path(\"/usr/local/globle/softs/slurm/19.05.4.1/sbin/slurmd\")\n    require(registered.is_file(), \"registered scheduler binary unavailable\")\n    observed = []\n    for directory in pathlib.Path(\"/proc\").iterdir():\n        if not directory.name.isdigit():\n            continue\n        try:\n            if (directory / \"comm\").read_text().strip() != \"slurmd\":\n                continue\n            require(directory.stat().st_uid == 0, \"scheduler daemon is not root owned\")\n            argv = (directory / \"cmdline\").read_bytes().split(b\"\\0\")\n            argv0 = os.fsdecode(argv[0])\n            try:\n                executable = pathlib.Path(os.readlink(directory / \"exe\"))\n                origin = \"actual_proc_exe\"\n            except OSError:\n                require(pathlib.Path(argv0).is_absolute(), \"cannot identify actual scheduler executable\")\n                executable = pathlib.Path(argv0)\n                origin = \"actual_proc_cmdline_absolute_executable\"\n            require(executable.resolve() == registered.resolve(), \"actual scheduler binary differs from registered installation\")\n            observed.append({\"pid\":int(directory.name),\"executable\":str(executable),\n                             \"argv0\":argv0,\"identity_origin\":origin})\n        except FileNotFoundError:\n            continue\n        except PermissionError:\n            continue\n    require(len(observed) == 1, \"exactly one identifiable actual scheduler daemon required\")\n    require(registered.stat().st_size < 32 * 1024**2, \"scheduler executable size unsupported\")\n    binary = registered.read_bytes()\n    require(binary.startswith(b\"\\x7fELF\"), \"scheduler executable is not ELF\")\n    version = captured(\"actual_scheduler_binary_version\", [str(registered), \"-V\"]).strip()\n    require(version == \"slurm 19.05.4\", \"actual scheduler binary version differs\")\n    markers = (\"processor limit reached (%u >= %d)\", \"siblings is %u (> %d), ignored\",\n               \"cores is %u (> %d), ignored\")\n    matched = [value for value in markers if value.encode()+b\"\\0\" in binary]\n    branch = \"non_hwloc_positive_compiled_branch\" if len(matched) == len(markers) else \"unproven_non_hwloc\"\n    print(json.dumps({\"stage\":\"actual_scheduler_cpu_mapping_binary\",\"daemon\":observed[0],\n        \"binary_path\":str(registered),\"binary_sha256\":hashlib.sha256(binary).hexdigest(),\n        \"binary_bytes\":len(binary),\"version\":version,\"branch\":branch,\n        \"matched_branch_exclusive_complete_strings\":matched}),flush=True)\n    return registered, branch\n\ndef proc_cpu_map(cpuinfo_text, node_text):\n    fields = dict(item.split(\"=\",1) for item in node_text.split() if \"=\" in item)\n    count = int(fields[\"CPUTot\"])\n    sockets, cores, threads = (int(fields[x]) for x in (\"Sockets\",\"CoresPerSocket\",\"ThreadsPerCore\"))\n    records = []\n    for block in re.split(r\"\\n\\s*\\n\",cpuinfo_text.strip()):\n        values = {k.strip():v.strip() for line in block.splitlines() if \":\" in line\n                  for k,v in [line.split(\":\",1)]}\n        require(all(k in values and values[k].isdigit()\n                    for k in (\"processor\",\"physical id\",\"core id\",\"siblings\",\"cpu cores\")),\n                \"incomplete CPU topology record\")\n        records.append({k:int(values[k]) for k in (\"processor\",\"physical id\",\"core id\",\"siblings\",\"cpu cores\")})\n    require([r[\"processor\"] for r in records] == list(range(count)), \"CPU records are not ordered complete indices\")\n    packages = {r[\"physical id\"] for r in records}\n    require(len(packages) == sockets and count == sockets*cores*threads, \"CPU socket topology differs\")\n    for package in packages:\n        selected = [r for r in records if r[\"physical id\"] == package]\n        require(len(selected) == cores*threads, \"CPU package size differs\")\n        core_ids = {r[\"core id\"] for r in selected}\n        require(len(core_ids) == cores, \"CPU package core count differs\")\n        require(all(sum(r[\"core id\"] == core for r in selected) == threads for core in core_ids),\n                \"CPU thread grouping differs\")\n    require(all(r[\"siblings\"] == cores*threads and r[\"cpu cores\"] == cores for r in records),\n            \"heterogeneous or inconsistent CPU topology\")\n    # Original Slurm sorts record indices. Ordered complete indices above are essential.\n    mapping = sorted(range(count), key=lambda i:(records[i][\"physical id\"],records[i][\"core id\"],records[i][\"processor\"]))\n    return mapping, records\n\ndef check_slurmd_hardware(text, node_text, node):\n    actual = dict(item.split(\"=\",1) for item in text.split() if \"=\" in item)\n    expected = dict(item.split(\"=\",1) for item in node_text.split() if \"=\" in item)\n    require(actual.get(\"NodeName\") == node, \"printed scheduler host differs\")\n    for source, target in ((\"CPUs\",\"CPUTot\"),(\"Boards\",\"Boards\"),(\"SocketsPerBoard\",\"Sockets\"),\n                           (\"CoresPerSocket\",\"CoresPerSocket\"),(\"ThreadsPerCore\",\"ThreadsPerCore\")):\n        require(int(actual[source]) == int(expected[target]), \"printed hardware topology differs: \"+source)\n    require(int(actual[\"Boards\"]) == 1, \"multi-board topology unsupported\")\n\ndef check_sysfs_cpu_records(records, read_text):\n    for row in records:\n        directory = \"/sys/devices/system/cpu/cpu\" + str(row[\"processor\"]) + \"/topology/\"\n        require(int(read_text(directory+\"physical_package_id\").strip()) == row[\"physical id\"], \"sysfs package differs\")\n        require(int(read_text(directory+\"core_id\").strip()) == row[\"core id\"], \"sysfs core differs\")\n        expected = {r[\"processor\"] for r in records if (r[\"physical id\"],r[\"core id\"]) == (row[\"physical id\"],row[\"core id\"])}\n        require(parse_ids(read_text(directory+\"thread_siblings_list\").strip()) == expected, \"sysfs sibling set differs\")\n\ndef allocated_linux_cpus(node, abstract_cpus):\n    config = captured(\"scheduler_cpu_mapping_configuration\", [\"scontrol\", \"show\", \"config\"])\n    fields = {k.strip(): v.strip() for line in config.splitlines() if \"=\" in line for k, v in [line.split(\"=\", 1)]}\n    require(fields.get(\"SLURM_VERSION\") == \"19.05.4\", \"CPU mapping source version differs\")\n    executable, branch = actual_slurmd_binary()\n    node_text = captured(\"allocated_node_cpu_topology\", [\"scontrol\", \"show\", \"node\", node])\n    # Uppercase -C exits during command-line parsing, before daemon/state initialization.\n    hardware = captured(\"actual_scheduler_readonly_hardware_print\", [str(executable), \"-C\"])\n    check_slurmd_hardware(hardware, node_text, node)\n    if branch == \"non_hwloc_positive_compiled_branch\":\n        cpuinfo = pathlib.Path(\"/proc/cpuinfo\").read_text()\n        require(len(cpuinfo) <= 2*1024**2, \"CPU information exceeds bound\")\n        mapping, records = proc_cpu_map(cpuinfo,node_text)\n        check_sysfs_cpu_records(records, lambda p:pathlib.Path(p).read_text())\n        origin = \"actual_slurmd_non_hwloc_compiled_branch_and_proc_cpuinfo_sysfs\"\n        evidence_sha = hashlib.sha256(cpuinfo.encode()).hexdigest()\n        print(json.dumps({\"stage\":\"complete_proc_cpu_topology_verified_against_sysfs\",\n            \"cpuinfo_sha256\":evidence_sha,\"records\":records}),flush=True)\n    else:\n        spool = fields.get(\"SlurmdSpoolDir\", \"\").replace(\"%h\",node).replace(\"%n\",node)\n        require(pathlib.Path(spool).is_absolute(), \"Slurmd spool directory unavailable\")\n        cached = pathlib.Path(spool)/\"hwloc_topo_whole.xml\"\n        require(cached.is_file() and cached.stat().st_size <= 2*1024**2,\n                \"compiled CPU mapping branch unproven and no actual scheduler hwloc topology\")\n        xml_text = cached.read_text()\n        mapping = topology_cpu_map(xml_text,node_text)\n        origin, evidence_sha = str(cached),hashlib.sha256(xml_text.encode()).hexdigest()\n    online = parse_ids(pathlib.Path(\"/sys/devices/system/cpu/online\").read_text().strip())\n    require(set(mapping) == online and abstract_cpus <= set(range(len(mapping))), \"online CPU topology differs\")\n    linux_cpus = {mapping[x] for x in abstract_cpus}\n    print(json.dumps({\"stage\":\"slurm_abstract_to_linux_cpu_mapping\",\"topology_origin\":origin,\n        \"topology_sha256\":evidence_sha,\"abstract_to_linux_cpu_map\":mapping,\n        \"assigned_abstract_cpu_ids\":sorted(abstract_cpus),\"assigned_linux_cpu_ids\":sorted(linux_cpus)}),flush=True)\n    return linux_cpus\n\ndef main():\n    expected = pathlib.Path(__file__).with_name(\"train.sh\")\n    require(len(sys.argv) == 2 and pathlib.Path(sys.argv[1]) == expected and expected.is_file() and not expected.is_symlink(), \"unexpected executable\")\n    job = os.environ.get(\"SLURM_JOB_ID\", \"\")\n    require(job.isdigit() and os.environ.get(\"SLURM_RESTART_COUNT\", \"0\") == \"0\", \"invalid or restarted job\")\n    gpu = os.environ.get(\"SLURM_JOB_GPUS\", \"\")\n    require(os.environ.get(\"CUDA_VISIBLE_DEVICES\") == gpu and os.environ.get(\"SLURM_CPUS_PER_TASK\") == \"4\", \"original allocation mask differs\")\n    node, cpus, gpu = parse_allocation(captured(\"own_detailed_allocation\", [\"scontrol\", \"-d\", \"show\", \"job\", job]), job, os.getuid(), gpu)\n    require(socket.gethostname().split(\".\")[0] == node, \"wrong host\")\n    cpus = allocated_linux_cpus(node, cpus)\n    before = set(os.sched_getaffinity(0))\n    require(cpus <= before, \"allocated CPU set unavailable\")\n    os.sched_setaffinity(0, cpus)\n    require(set(os.sched_getaffinity(0)) == cpus, \"CPU affinity binding failed\")\n    inventory = captured(\"gpu_inventory\", [\"nvidia-smi\", \"--query-gpu=index,uuid,name,memory.total,memory.free,memory.used\", \"--format=csv,noheader,nounits\"])\n    gres_path = pathlib.Path(\"/usr/local/globle/softs/slurm/19.05.4.1/etc/gres.conf\")\n    gres_text = gres_path.read_text()\n    gpu_xml = captured(\"gpu_device_file_uuid_mapping\", [\"nvidia-smi\", \"-q\", \"-x\"])\n    device, minor, uuid = allocated_gpu_uuid(gpu_xml, gres_text, gpu)\n    device_stat = pathlib.Path(device).stat()\n    require(os.major(device_stat.st_rdev) == 195 and os.minor(device_stat.st_rdev) == minor, \"allocated GPU character device differs\")\n    selected = select_gpu(inventory, uuid)\n    print(json.dumps({\"stage\":\"allocated_gres_device_to_uuid\",\"gres_config\":str(gres_path),\n        \"gres_sha256\":hashlib.sha256(gres_text.encode()).hexdigest(),\"allocated_gres_index\":gpu,\n        \"device_file\":device,\"device_minor\":minor,\"gpu_uuid\":uuid,\"nvidia_smi_index\":selected[0]}),flush=True)\n    rows = compute_rows(captured(\"existing_compute_processes_observed_not_cancelled\", [\"nvidia-smi\", \"--query-compute-apps=gpu_uuid,pid,used_gpu_memory\", \"--format=csv,noheader,nounits\"]))\n    require(not any(row[0] == selected[1] for row in rows), \"allocated GPU already has a compute process; do not interfere\")\n    mem = {}\n    for line in pathlib.Path(\"/proc/meminfo\").read_text().splitlines():\n        key, value = line.split(\":\", 1)\n        if key in (\"MemTotal\", \"MemAvailable\"):\n            mem[key] = int(value.strip().split()[0]) * 1024\n    require(mem.get(\"MemAvailable\", 0) >= 32 * 1024**3, \"less than 32 GiB available host memory\")\n    os.environ[\"CUDA_VISIBLE_DEVICES\"] = selected[1]\n    os.environ[\"KDPP_ALLOCATED_GPU_UUID\"] = selected[1]\n    os.environ[\"KDPP_ALLOCATED_CPU_IDS\"] = \",\".join(str(x) for x in sorted(cpus))\n    print(json.dumps(dict(status=\"OWN_ALLOCATED_RESOURCES_BOUND\", job_id=job, node=node,\n        assigned_gpu_index=gpu, assigned_gpu_uuid=selected[1], cpu_affinity_before=sorted(before),\n        cpu_affinity_after=sorted(cpus), host_memory=mem, other_gpu_process_rows=len(rows),\n        gpu_inventory_selected=selected, other_jobs_modified=0, hardware_device_cgroup_enforcement_claimed=False)), flush=True)\n    os.execv(\"/bin/bash\", [\"/bin/bash\", str(expected), \"--resource-bound\"])\n\nif __name__ == \"__main__\":\n    main()\n"
with (launch/'resource_bind.py').open('xb') as f: f.write(binding_script.encode())
script_bytes=script.encode()
launch_script=launch/'train.sh'
with launch_script.open('xb') as f: f.write(script_bytes)
baseline=dict(binding_script_sha256=sha(binding_script.encode()),resource_scope='OWN_ASSIGNED_GPU_AND_CPU_SHARED_NODE',request_sequence=66,experiment_id=experiment_id,execution_id=execution_id,basin_id='09035800',state_dimension=18,configuration_sha256=sha(config_bytes),source_root=str(source),source_sha256=configuration['source_sha256'],archive_sha256='737d7044e6c239d16a13d28ce1d7bd62fe8f58c6bd304ee89b3a681edc230c38',deployed_files=51,run_directory=str(run_directory),audit_report=str(audit_report),before_runs=before_runs,node='ngu203',partition='hgpu8',gpu_name='NVIDIA A800-SXM4-80GB',cpus=4,gpus=1,time_limit='12:00:00',requeue=False,global_preemption='OFF',training_attempt=2,new_deployment_training_attempt=1,previous_failed_training_execution='DAILY_CAMELS_KNET_PER_BASIN_PILOT_09035800_A800_TRAIN1_SEQ24',previous_failed_training_resumed=False,training_epochs=80,recovery_requests_used=0,sealed_training_script_sha256='f7ed33fd12a3db262f5d7f9b730fd841cd9de2f2a21d021536855f5602689bcf',node_wrapper_sha256=sha(script_bytes),node_wrapper_bytes=len(script_bytes),accepted_runtime_job='223590',accepted_runtime_result_sha256='2deac457fe483af6e0abaf399e37aec305354616a4899ff491e753cdda9d6dd4',accepted_runtime_files=accepted_runtime_files,prior_completed_first_execution=completed_first_run,prior_completed_first_terminal_evidence=first_terminal_files,prior_completed_first_audit_sha256='293e0476d2f8f01a8a2a0580c022fa5e225e8047cd8d4b3155c72c53959e10da',prior_completed_first_job_id=223629,prior_completed_first_independent_terminal_acceptance_sha256='da36ce54be233d80b782fc91b03ad3b17a15cb5f04062777730b2b98d2de544d',prior_completed_second_execution=completed_second_run,prior_completed_second_terminal_evidence=second_terminal_files,prior_completed_second_audit_sha256='55136aa929c8a06ed6ab37eee306f8fb02949e68e157390ddb76fdfedc230b1a',prior_completed_second_job_id=223689,prior_completed_second_independent_terminal_acceptance_sha256='5e83a39b81912d3fa0fec9fa34a25301f98b12be7e28fb0c1c125af97f70e80a',prior_completed_second_scientific_capability_status='FAILED',prior_completed_second_relative_accuracy_status='KALMANNET_ADVANTAGE',formal_evaluation_access_count=0)
baseline.update(accepted_runtime_original_state='FAILED',accepted_runtime_original_exit_code='1:0',accepted_runtime_qualification_sha256=sha(qualification_bytes),accepted_runtime_qualification_verifier_sha256=qualification['verifier_sha256'],accepted_postcheck_result_sha256=qualification['result56_sha256'],original_runtime_failure_preserved=True)
baseline_bytes=(json.dumps(baseline,sort_keys=True,allow_nan=False)+'\n').encode()
with (launch/'pre_submit_baseline.json').open('xb') as f: f.write(baseline_bytes)
print(json.dumps(dict(pre_submit_baseline=baseline,baseline_sha256=sha(baseline_bytes)),sort_keys=True),flush=True)
sbatch_environment={key:value for key,value in os.environ.items() if not key.startswith('SBATCH_')}
submission=run(['sbatch',str(launch_script)],cwd=str(source),timeout=60,env=sbatch_environment)
emit('SBATCH_THIRD_BASIN_TRAINING_ONCE',submission)
job_matches=re.findall(r'(?m)^Submitted batch job ([0-9]+)\s*$',submission.stdout.decode())
if not job_matches and re.fullmatch(r'[0-9]+(?:;[A-Za-z0-9_.-]+)?\s*',submission.stdout.decode()):
    job_matches=[submission.stdout.decode().strip().split(';')[0]]
receipt=dict(request_sequence=66,execution_id=execution_id,submission_exit_code=submission.returncode,stdout=submission.stdout.decode(),stderr=submission.stderr.decode(),job_matches=job_matches,baseline_sha256=sha(baseline_bytes),node_wrapper_sha256=sha(script_bytes),training_submissions=1)
with (launch/'submission_receipt.json').open('xb') as f: f.write((json.dumps(receipt,sort_keys=True)+'\n').encode())
require(submission.returncode==0 and len(job_matches)==1,'submission ambiguous or failed; read-only reconciliation only; no fresh execution or resubmission')
job_id=job_matches[0]
emit('SUBMITTED_TRAINING_CONTROLLER_RECORD',run(['scontrol','show','job',job_id]))
verify_source()
after_runs=sorted(p.name for p in runs.iterdir())
require(set(after_runs) in [set(before_runs),set(before_runs)|{execution_id}],'unrelated run namespace changed')
print(json.dumps(dict(status='TRAINING_SUBMITTED_NOT_YET_VERIFIED_RUNNING',request_sequence=66,job_id=job_id,execution_id=execution_id,experiment_id=experiment_id,basin_id='09035800',node='ngu203',run_directory=str(run_directory),launch_directory=str(launch),audit_report=str(audit_report),baseline_sha256=sha(baseline_bytes),node_wrapper_sha256=sha(script_bytes),training_submissions=1,formal_evaluation_access_count=0),sort_keys=True),flush=True)


PY_SUBMISSION
