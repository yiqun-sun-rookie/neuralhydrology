#!/usr/bin/env bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1 PYTHONOPTIMIZE=0
printf '%s\n' 'channel=kalmannet-daily-perbasin sequence=50 purpose=single-card-diagnostic223564-read-only-terminal'
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY_COLLECT'
import hashlib, json, os, pathlib, re, subprocess, sys, time
root = pathlib.Path('/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901')
source = root / 'deployments/DAILY_CAMELS_KNET_PER_BASIN_V2_BUNDLE_HISTORYFIX1_DEPLOY_SEQ43/source'
sequence = 50
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


import base64, datetime, stat, socket
job_id = 223564
diagnostic = root / 'gpu_sharing_diagnostic_20260907/request49'
require(diagnostic.is_dir() and diagnostic.resolve() == diagnostic and not diagnostic.is_symlink(), 'diagnostic directory differs')
print(json.dumps({'stage':'TERMINAL_COLLECTION_START','job_id':job_id,'observed_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'host':socket.gethostname(),'diagnostic_directory':str(diagnostic)}),flush=True)
def raw_bytes(data):
    return {'bytes':len(data),'sha256':sha(data),'base64':base64.b64encode(data).decode('ascii')}
for label,args in [
    ('DIAGNOSTIC_ACCOUNTING',['sacct','-n','-P','-j',str(job_id),'--format=JobID,JobName%100,State,ExitCode,Elapsed,Submit,Start,End,NodeList,AllocCPUS']),
    ('DIAGNOSTIC_CURRENT_JOB',['scontrol','-d','show','job',str(job_id)]),
    ('DIAGNOSTIC_CURRENT_QUEUE',['squeue','-h','-j',str(job_id),'-o','%i|%200j|%T|%N|%C|%b']),
    ('CURRENT_TARGET_NODE',['scontrol','-d','show','node','ngu201'])
]:
    record={'stage':label,'argv':args,'started_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat()}
    try:
        result=run(args,timeout=30)
        record.update(returncode=result.returncode,stdout=raw_bytes(result.stdout),stderr=raw_bytes(result.stderr))
        if len(result.stdout)>262144 or len(result.stderr)>65536:record['collection_error']='query exceeds bounded output'
    except subprocess.TimeoutExpired as exc:
        record.update(returncode=None,query_error_type='TimeoutExpired',query_error=str(exc),stdout=raw_bytes(exc.stdout or b''),stderr=raw_bytes(exc.stderr or b''))
    except Exception as exc:
        record.update(returncode=None,query_error_type=type(exc).__name__,query_error=str(exc))
    record['finished_at_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat()
    print(json.dumps(record,sort_keys=True),flush=True)
allowed = {'probe.py','probe.slurm','submission-intent.json','submission-receipt.json','pre_submit_snapshot.json','submission_lock.json','submission_receipt.json','submission_started.json','pre_submit_baseline.json','submit_once.json','submission.json','submit_receipt.json','slurm-'+str(job_id)+'.stdout','slurm-'+str(job_id)+'.stderr'}
inventory=[]
for path in sorted(diagnostic.iterdir()):
    st=path.lstat()
    item={'name':path.name,'bytes':st.st_size,'mtime_ns':st.st_mtime_ns,'is_regular':stat.S_ISREG(st.st_mode),'is_symlink':path.is_symlink()}
    inventory.append(item)
    if path.name not in allowed:
        print(json.dumps({'stage':'FILE_NOT_READ_OUTSIDE_EXACT_ALLOWLIST',**item}),flush=True)
        continue
    require(path.resolve()==path and not path.is_symlink() and stat.S_ISREG(st.st_mode),'diagnostic file not a plain in-scope file')
    require(st.st_size<=1048576,'diagnostic text exceeds bounded read')
    data=path.read_bytes()
    print(json.dumps({'stage':'EXACT_DIAGNOSTIC_TEXT','path':str(path),'content':raw_bytes(data)},sort_keys=True),flush=True)
print(json.dumps({'stage':'DIAGNOSTIC_FILE_INVENTORY','files':inventory}),flush=True)
recovery = root/'node_recovery_20260907'
print(json.dumps({'stage':'UNCHANGED_RECOVERY_ABSENCE','paths':[{'path':str(p),'exists':p.exists(),'is_symlink':p.is_symlink()} for p in (recovery/'historyfix1_runtime_recovery1_seq46',recovery/'historyfix1_runtime_recovery_once.json')]}),flush=True)
print(json.dumps({'status':'READ_ONLY_DIAGNOSTIC_TERMINAL_COLLECTION_NOT_TRAINING_QUALIFICATION','job_id':job_id,'request_sequence':sequence,'observed_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'new_jobs_submitted':0,'remote_task_files_written':0,'training_updates':0,'formal_evaluation_accesses':0,'checkpoint_downloads':0}),flush=True)

PY_COLLECT
