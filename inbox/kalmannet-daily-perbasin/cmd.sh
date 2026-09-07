#!/usr/bin/env bash
set -eo pipefail
printf '%s\n' 'channel=kalmannet-daily-perbasin sequence=52 purpose=readonly-original-runtime-recovery-terminal'
export PYTHONDONTWRITEBYTECODE=1 PYTHONOPTIMIZE=0
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B -u - <<'PY_COLLECT'
import hashlib, json, os, pathlib, re, subprocess, sys, time
root = pathlib.Path('/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901')
source = root / 'deployments/DAILY_CAMELS_KNET_PER_BASIN_V2_BUNDLE_HISTORYFIX1_DEPLOY_SEQ43/source'
sequence = 52
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


import base64, xml.etree.ElementTree as ET
audit=root/'node_recovery_20260907/historyfix1_runtime_recovery1_seq51'
expected_job='223573'
expected_baseline='236c5f07329411427d0de7f8b7c552567a5bdb890b31b089318c0376d8e4aae3'
expected_script='329a9de595b1184df2051b36106fe4657f0099b2264618734c8a1906ccf7c580'
expected_binding='417103ee5970a152d4c2eb3bdac36fd928817b7a28c099148b481acd4a66070a'
require(audit.is_dir() and audit.resolve()==audit and not audit.is_symlink(),'runtime audit missing or linked')
texts={}
def read_text(name,expected=None):
    p=audit/name
    require(p.is_file() and not p.is_symlink() and p.resolve()==p,'missing audit text '+name)
    data=p.read_bytes()
    require(len(data)<=4*1024**2,'text exceeds bound '+name)
    if expected: require(sha(data)==expected,'audit text changed '+name)
    text=data.decode('utf-8');texts[name]=text
    print(json.dumps({'audit_file':name,'size_bytes':len(data),'sha256':sha(data),'text':text},sort_keys=True),flush=True)
    return text
baseline=json.loads(read_text('pre_submit_baseline.json',expected_baseline))
receipt=json.loads(read_text('submission_receipt.json'))
read_text('runtime_gate.sh',expected_script)
read_text('resource_bind.py',expected_binding)
require(baseline['request_sequence']==51 and baseline['runtime_recovery_attempt']==1 and baseline['new_build_runtime_attempt']==2 and baseline['training_submissions']==0,'runtime baseline differs')
require(receipt['job_matches']==[expected_job] and receipt['request_sequence']==51 and receipt['submission_exit_code']==0 and receipt['baseline_sha256']==expected_baseline,'job identity differs')
ledger=root/'node_recovery_20260907/historyfix1_runtime_recovery_once.json'
ledger_bytes=ledger.read_bytes()
require(not ledger.is_symlink() and sha(ledger_bytes)==baseline['runtime_recovery_ledger_sha256'],'fixed recovery ledger changed')
print(json.dumps({'recovery_ledger_sha256':sha(ledger_bytes),'recovery_ledger':json.loads(ledger_bytes)},sort_keys=True),flush=True)
queries={}
for label,args in [('runtime_accounting',['sacct','-n','-P','-j',expected_job,'--format=JobID,JobName%80,State,ExitCode,Elapsed,NodeList,AllocCPUS,ReqCPUS']),
 ('runtime_queue',['squeue','-h','-j',expected_job,'-o','%i|%j|%T|%P|%N|%R']),
 ('runtime_controller',['scontrol','-d','show','job',expected_job]),
 ('current_user_queue',['squeue','-h','-u',str(os.getuid()),'-o','%i|%200j|%T|%N'])]:
    q=run(args);queries[label]=q
    print(json.dumps({'query':label,'args':args,'exit_code':q.returncode,'stdout':q.stdout.decode(),'stderr':q.stderr.decode()},sort_keys=True),flush=True)
names=['slurm-'+expected_job+'.stdout','slurm-'+expected_job+'.stderr','history_binding_pytest.stdout','history_binding_pytest.stderr','history_binding_junit.xml','test_support/test_support_manifest.json']+[f'gate_{basin}.{stream}' for basin in ['04105700','08070200','09035800'] for stream in ['stdout','stderr']]
for name in names:
    if (audit/name).is_file(): read_text(name)
    else: print(json.dumps({'audit_file':name,'exists':False}),flush=True)
smb=(audit/'test_support/test_support_manifest.json').read_bytes()
require(sha(smb)=='a3d2a9cdff2a5b2f507afd4426e60297495c3bd417f2129620a082239a44804c','support manifest changed')
sm=json.loads(smb)
sf={p.relative_to(audit/'test_support').as_posix():p for p in (audit/'test_support').rglob('*') if p.is_file()}
require(set(sf)==set(sm['member_sha256'])|{'test_support_manifest.json'},'support file set changed')
for name,h in sm['member_sha256'].items():
    require(not sf[name].is_symlink() and sha(sf[name].read_bytes())==h,'support file changed '+name)
support_archive=(audit/'isolated_pytest_support.tar.gz').read_bytes()
require(len(support_archive)==397630 and sha(support_archive)=='4d96b1169a5ab9aa654125fc339f78baeb6f815089313889f8ffdf5829f8b034','support archive changed')
synthetic_files=0;synthetic_bytes=0
for p in audit.rglob('*'):
    require(not p.is_symlink(),'linked runtime member')
    if p.is_file() and 'synthetic_tmp' in p.relative_to(audit).parts:
        synthetic_files+=1;synthetic_bytes+=p.stat().st_size
print(json.dumps({'support_integrity':'PASS','support_files':len(sf),'synthetic_inventory_metadata_only':{'files':synthetic_files,'bytes':synthetic_bytes},'synthetic_checkpoint_contents_returned':0}),flush=True)
require(preserved_snapshot()==json.loads((source.parent/'pre_deploy_preserved_snapshot.json').read_text()),'old protected state changed')
require(not any((audit/'output_parent').iterdir()),'nontraining output parent not empty')
rows=[line.split('|') for line in queries['runtime_accounting'].stdout.decode().splitlines() if line.strip()]
main=[row for row in rows if row[0]==expected_job]
stdout=texts.get('slurm-'+expected_job+'.stdout','')
objs=[]
for line in stdout.splitlines():
    if line.startswith('{'):
        try: objs.append(json.loads(line))
        except json.JSONDecodeError: pass
cases=[]
if 'history_binding_junit.xml' in texts:
    cases=list(ET.fromstring(texts['history_binding_junit.xml']).iter('testcase'))
print(json.dumps({'status':'EXACT_RUNTIME_EVIDENCE_COLLECTED_FOR_INDEPENDENT_ACCEPTANCE','request_sequence':52,'submission_sequence':51,'job_id':expected_job,
 'accounting_main':main,'runtime_final_marker_present':'HISTORYFIX1_RUNTIME_AND_SYNTHETIC_GATE_FINISHED real_gpu_optimizer_steps=0 cpu_toy_optimizer_updates=405 scientific_training_submissions=0' in stdout,
 'resource_binding':[o for o in objs if o.get('status') in ['OWN_ALLOCATED_RESOURCES_BOUND','ACTUAL_ASSIGNED_GPU_AND_CPU_PASS']],
 'synthetic_acceptance':[o for o in objs if o.get('status')=='HISTORYFIX1_SYNTHETIC_CPU_ENTRYPOINT_PASS'],
 'junit_cases':[dict(name=x.attrib.get('name'),failure=x.find('failure') is not None,error=x.find('error') is not None,skipped=x.find('skipped') is not None) for x in cases],
 'all_required_texts_exist':all(name in texts for name in names),'required_stderr_all_exactly_empty':all(texts.get(name) == '' for name in names if name.endswith('.stderr')),
 'task_file_writes':0,'training_submissions':0,'runtime_submissions':0,'formal_evaluation_access_count':0},sort_keys=True),flush=True)

PY_COLLECT
