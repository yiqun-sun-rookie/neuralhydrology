#!/usr/bin/env bash
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
python -B - <<'PY'
import datetime,hashlib,json,pathlib,subprocess,sys
import torch
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261012_recovery_003')
case='explicit_gru__historical_capacity'
rid=case+'__tune_branch__filter_joint__s101__lr0p003'
run=root/'runs'/rid
expected_code='19bf9eb19614f62a329da1cac2f2ec377558ff7f72d32ac5f5d935f30415eca0'
expected_config='440434f37337ea1c17cc6007dbfe203f49ff730b08fb21c4c65af24446ba54ea'
expected_checkpoint='36ed49fb56c1032ca85c9c21378dfe2e766392774f234d88e2814cb9e44897e8'
expected_failure='5e52a61c25ce1444a056a0017faeb7513b77f8788aee78495e82f20de313dbaf'
def sha(path):
    h=hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda:f.read(1048576),b''):h.update(block)
    return h.hexdigest()
def read(path):return json.loads(path.read_text())
def identity(path):
    s=path.stat()
    return {'sha256':sha(path),'bytes':s.st_size,'mtime_ns':s.st_mtime_ns}
def finite(value):
    if isinstance(value,torch.Tensor):return bool(torch.isfinite(value).all())
    if isinstance(value,dict):return all(finite(x) for x in value.values())
    if isinstance(value,(list,tuple)):return all(finite(x) for x in value)
    return True
sys.path.insert(0,str(root))
from src.scheduler import code_identity,digest_json,seal_group,verify_parent_binding,validate_registry
from dataclasses import asdict
assert code_identity(root)==expected_code
config=read(run/'config.json');effective=config['effective_config'];registered=config['registration']
assert sha(run/'config.json')==expected_config and sha(run/'continuation.pt')==expected_checkpoint
assert sha(run/'failure.json')==expected_failure
assert registered['exp_id']==rid and registered['method']=='filter_joint' and registered['seed']==101
assert registered['train_years']==[2017,2018,2019,2020] and effective['learning_rate']==.003
protocol=read(root/'configs/protocol-v3.json');auth=read(root/'records/authorization.json')
assert effective['code_hash']==auth['code_hash']==expected_code
assert config['protocol_sha256']==auth['protocol_sha256']==sha(root/'configs/protocol-v3.json')
assert auth['authority']['formal_training'] and not auth.get('evaluation_year_reads',False)
registry=read(root/'configs/registry-v3.json');validate_registry(registry,protocol)
assert [r for r in registry['runs'] if r['exp_id']==rid]==[registered]
group=read(root/'records'/case/'tune_branch_group_configs.json')
assert group[rid]==config and len(group)==12
prep=read(root/'records/data_preparation_complete.json')
assert prep['status']=='admitted' and prep['code_hash']==expected_code
manifest=read(root/'prepared/tuning/manifest.json')
assert manifest['status']=='admitted' and not manifest.get('evaluation_year_reads',False)
assert digest_json(manifest)==effective['training_data_hash']
assert manifest['tide_source_hash']==effective['tide_source_hash']
training_entries=[e for e in manifest['files'] if 'tuning_train' in e.get('phases',[])]
assert training_entries and all(set(e['years']).issubset({2017,2018,2019,2020}) for e in training_entries)
assert {e['role'] for e in training_entries}=={'realtime_inputs','qc_labels','astronomical_tide'}
source_files={name:identity(run/name) for name in ('config.json','continuation.pt','failure.json','metrics.json')}
state=torch.load(run/'continuation.pt',map_location='cpu',weights_only=True)
metrics=read(run/'metrics.json')
assert state['config_sha256']==expected_config and finite(state)
assert all(len(state[k])==44 for k in ('values','train_metrics','shuffle_hashes'))
assert metrics['validation_mae_cm']==state['values'] and metrics['train_metrics']==state['train_metrics']
assert metrics['shuffle_hashes']==state['shuffle_hashes']
steps=[float(x['step']) for x in state['optimizer']['state'].values()]
assert steps and min(steps)==max(steps)==sum(len(row) for row in state['train_metrics'])
failure=read(run/'failure.json')
assert failure['epochs_completed']==44 and failure['type']=='FilterFailure'
assert failure['reason']=='covariance not positive definite after permitted jitter'
outcome=read(root/'records'/case/'tune_foundation_group_outcome.json')
assert len(outcome['members'])==3 and outcome['seal']['epochs']==400
checked=seal_group(case+'__tune_foundation_group__seal',outcome['members'],400,list(outcome['members']))
assert asdict(checked)==dict(outcome['seal'],member_ids=tuple(outcome['seal']['member_ids']))
verify_parent_binding(registered,effective,{checked.group_id:checked})
parent_files={}
for member,result in outcome['members'].items():
    path=pathlib.Path(result['checkpoint_path'])
    assert sha(path)==result['checkpoint_sha256']
    parent_files[member]={'path':str(path),'sha256':result['checkpoint_sha256'],'epochs':result['epochs']}
jobs=read(root/'records/scheduler_jobs.json');job=str(jobs[case]);assert job=='241957'
queries=[]
for c in [['squeue','-h','-u','sunyiq','-o','%i|%j|%T|%N'],['sacct','-n','-X','-j',job,'--format=JobID,State,ExitCode,Start,End,NodeList','-P']]:
    p=subprocess.run(c,capture_output=True,text=True,timeout=30)
    queries.append({'command':c,'returncode':p.returncode,'stdout':p.stdout,'stderr':p.stderr})
assert all(q['returncode']==0 for q in queries)
assert not any(line.split('|')[0]==job for line in queries[0]['stdout'].splitlines())
assert job+'|FAILED|1:0|' in queries[1]['stdout']
active_diagnostics=[line for line in queries[0]['stdout'].splitlines() if len(line.split('|'))>1 and line.split('|')[1].startswith('zj_gru_cov_diag_')]
code_files=sorted([*root.joinpath('src').glob('*.py'),*root.joinpath('scripts').glob('*.py'),*root.joinpath('vendor/pytides').glob('*.py')])
code_hashes={p.relative_to(root).as_posix():sha(p) for p in code_files}
assert all(identity(run/name)==before for name,before in source_files.items())
assert code_identity(root)==expected_code
print(json.dumps({'status':'read_only_covariance_diagnostic_source_admitted','checked_at_beijing':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
    'source_root':str(root),'source_job':job,'case':case,'run_id':rid,'source_code_hash':expected_code,'source_code_file_hashes':code_hashes,
    'source_run_files':source_files,'source_failure':failure,'expected_saved_epoch':44,'replayed_epoch':45,
    'expected_device_identity':effective['device_identity'],'optimizer_steps':min(steps),'saved_histories_match_metrics':True,
    'all_checkpoint_tensors_finite':True,'source_bytes_unchanged':True,'parent_completed_member_epochs':1200,
    'parent_checkpoints':parent_files,'training_phase_only':'tuning_train','training_years':[2017,2018,2019,2020],
    'training_input_values_read':False,'selection_input_values_read':False,'evaluation_values_read':False,
    'active_covariance_diagnostic_jobs':active_diagnostics,'scheduler_queries':queries,
    'new_job_submitted':False,'training_or_checkpoint_files_written':False,'scientific_rules_changed':False},sort_keys=True))
PY
