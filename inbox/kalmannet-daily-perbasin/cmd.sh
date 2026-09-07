#!/usr/bin/env bash
set -eo pipefail
printf '%s\n' 'channel=kalmannet-daily-perbasin sequence=56 purpose=readonly-postcheck-residual-classification-no-compute'
export PYTHONDONTWRITEBYTECODE=1 PYTHONOPTIMIZE=0
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B -u - <<'PY_COLLECT'
import hashlib, json, os, pathlib, re, subprocess, sys, time
root = pathlib.Path('/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901')
source = root / 'deployments/DAILY_CAMELS_KNET_PER_BASIN_V2_BUNDLE_HISTORYFIX1_DEPLOY_SEQ43/source'
sequence = 56
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

audit=root/'node_recovery_20260907/historyfix1_runtime_attempt3_seq53'
require(audit.is_dir() and not audit.is_symlink() and audit.resolve()==audit,'runtime audit changed')
text_fingerprints={"pre_submit_baseline.json":{"bytes":2025,"sha256":"813d3287e02463851712ae44f66a7981b468a99510fbad4b9e2afcab6b38d48d"},"submission_receipt.json":{"bytes":368,"sha256":"77ca770a65b15d0ceb24dee3a5aa7345ced539434fb0335619368fcca75740c9"},"runtime_gate.sh":{"bytes":22339,"sha256":"8909b749e16cbc7d4a9610f2f1d87b844f2052f663d2cc0579c7b1a2a0a02d08"},"resource_bind.py":{"bytes":16968,"sha256":"6d67fe1b965c6af590f2cdc08a49a1d817a2d0e656926c03d76837ff4315c96b"},"slurm-223590.stdout":{"bytes":156333,"sha256":"0d74b9756e2eac5e9538aef72ee47c6114817d02eae1313b277d89d7d8a676ae"},"slurm-223590.stderr":{"bytes":137,"sha256":"61b12692da340e5bd3a9adea860752fa8f6c439a6c1354bd2a7156ec7c1aa9a8"},"history_binding_pytest.stdout":{"bytes":1823,"sha256":"f6e416ec99358785d6c7b64f9dd4f7abe7ae6246899610dde39be6a413b949ff"},"history_binding_pytest.stderr":{"bytes":0,"sha256":"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"},"history_binding_junit.xml":{"bytes":5387,"sha256":"70921cba1e97fcb73d7b6a34a69f21338aa128770d4dba956f47a31ced6caac3"},"test_support/test_support_manifest.json":{"bytes":19284,"sha256":"a3d2a9cdff2a5b2f507afd4426e60297495c3bd417f2129620a082239a44804c"},"gate_04105700.stdout":{"bytes":866,"sha256":"785b2bb4eb01b6b2bde465123e4e752fe20d78c6ca7406f98a875e6ca94f099f"},"gate_04105700.stderr":{"bytes":0,"sha256":"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"},"gate_08070200.stdout":{"bytes":869,"sha256":"30ddb7090c1cef673105dfedbb3d426c5c0c23317feb1b78fb7eacafae691b64"},"gate_08070200.stderr":{"bytes":0,"sha256":"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"},"gate_09035800.stdout":{"bytes":868,"sha256":"122419cfa1462a3eef4634fbf9aaf5e475d3e2511513360042aa483d150cc76f"},"gate_09035800.stderr":{"bytes":0,"sha256":"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}}
for name,item in text_fingerprints.items():
    p=audit/name
    require(p.is_file() and not p.is_symlink(),'terminal text missing or linked')
    data=p.read_bytes()
    require(len(data)==item['bytes'] and sha(data)==item['sha256'],'terminal text changed: '+name)
ledger=root/'node_recovery_20260907/historyfix1_runtime_attempt3_seq53.json'
require(not ledger.is_symlink() and sha(ledger.read_bytes())=='5e54e01e9a249a58593d25bbae89e7ae3f9d3f15e2f79966a575e6ee63f1d2b3','third runtime registration changed')
q=run(['sacct','-n','-P','-j','223590','--format=JobID,State,ExitCode,Elapsed,NodeList'])
print(json.dumps({'query':'actual_terminal_accounting','exit_code':q.returncode,'stdout':q.stdout.decode(),'stderr':q.stderr.decode()}),flush=True)
require(q.returncode==0 and any(x.split('|')[:3]==['223590','FAILED','1:0'] for x in q.stdout.decode().splitlines()),'previous terminal state changed')
sm=json.loads((audit/'test_support/test_support_manifest.json').read_bytes())
sf={p.relative_to(audit/'test_support').as_posix():p for p in (audit/'test_support').rglob('*') if p.is_file()}
require(set(sf)==set(sm['member_sha256'])|{'test_support_manifest.json'},'support namespace changed')
for name,h in sm['member_sha256'].items():
    require(not sf[name].is_symlink() and sha(sf[name].read_bytes())==h,'support changed')
require(sha((audit/'isolated_pytest_support.tar.gz').read_bytes())=='4d96b1169a5ab9aa654125fc339f78baeb6f815089313889f8ffdf5829f8b034','support archive changed')
residuals=[]
for name in ('output_parent','tmp','cache'):
    base=audit/name
    require(base.is_dir() and not base.is_symlink() and base.resolve()==base,'audit residual root differs')
    for directory,dirs,files in os.walk(base,followlinks=False):
        for member in dirs+files:
            p=pathlib.Path(directory)/member
            info={'path':p.relative_to(audit).as_posix(),'mtime_ns':p.lstat().st_mtime_ns}
            if p.is_symlink():
                info.update(kind='symlink',target=os.readlink(p),contents_followed=False)
            elif p.is_dir():
                info.update(kind='directory',children=sorted(x.name for x in p.iterdir()))
            elif p.is_file():
                size=p.stat().st_size;info.update(kind='file',size_bytes=size)
                if size<=32*1024**2:
                    data=p.read_bytes();info['sha256']=sha(data)
                    if p.suffix in {'.py','.json','.txt','.log'} and size<=4096:
                        try: info['bounded_text']=data.decode('utf-8')
                        except UnicodeDecodeError: info['utf8']=False
                else: info['sha256_status']='NOT_READ_EXCEEDS_BOUND'
            else: info.update(kind='other')
            residuals.append(info)
print(json.dumps({'post_test_residual_inventory_readonly':residuals,'residual_roots':{n:sorted(x.name for x in (audit/n).iterdir()) for n in ('output_parent','tmp','cache')}}),flush=True)
require(not list((audit/'output_parent').iterdir()),'numeric runtime unexpectedly retained output')
synthetic=[]
links=[]
base=audit/'synthetic_tmp'
require(base.is_dir() and not base.is_symlink(),'synthetic root missing or linked')
for directory,dirs,files in os.walk(base,followlinks=False):
    for member in dirs+files:
        p=pathlib.Path(directory)/member
        if p.is_symlink():
            links.append({'path':p.relative_to(audit).as_posix(),'target':os.readlink(p)})
        elif p.is_file():
            synthetic.append({'path':p.relative_to(audit).as_posix(),'size_bytes':p.stat().st_size,'mtime_ns':p.stat().st_mtime_ns})
require(len(synthetic)==1338 and sum(x['size_bytes'] for x in synthetic)==56767998,'synthetic terminal inventory totals changed')
print(json.dumps({'synthetic_terminal_file_metadata_only':synthetic,'synthetic_link_metadata_only':links,'synthetic_checkpoint_contents_returned':0}),flush=True)
require(preserved_snapshot()==json.loads((source.parent/'pre_deploy_preserved_snapshot.json').read_text()),'old protected state changed')
print(json.dumps({'status':'POSTCHECK_RESIDUAL_READONLY_EVIDENCE_COMPLETE_NOT_RUNTIME_ACCEPTANCE','request_sequence':56,'job_id':'223590','terminal_texts_verified':len(text_fingerprints),'old_failure_preserved':True,'scientific_submissions':0,'compute_submissions':0,'remote_task_file_writes':0,'checkpoint_downloads':0,'formal_evaluation_access_count':0}),flush=True)
PY_COLLECT
