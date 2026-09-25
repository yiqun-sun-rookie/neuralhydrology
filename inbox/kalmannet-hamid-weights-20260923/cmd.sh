#!/bin/bash
set -eo pipefail
sequence=37
root=/data1/home/sunyiq/kalmannet_hamid_weights_20260923_v1
date -u '+SNAPSHOT_UTC=%Y-%m-%dT%H:%M:%SZ'
printf '\nFOURTH_CELL_SCHEDULER\n'
sacct -X -j 227699 -n -P --format=JobIDRaw,JobName,State,ExitCode,Elapsed,NodeList || true
printf '\nFOURTH_CELL_INDEPENDENT_FAILURE_AUDIT\n'
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY'
import hashlib,json
from collections import Counter,defaultdict
from pathlib import Path
root=Path('/data1/home/sunyiq/kalmannet_hamid_weights_20260923_v1')
pkg=root/'formal_package_v3'
out=root/'formal_attempt_003/runs/objective-current-0-highflow-2-seed-43'
logs=root/'formal_attempt_003/logs'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(n):return json.loads((out/n).read_text())
assert sha(pkg/'manifest.json')=='4bd8fe167bb5d6932a25161e9855bfdf03f656352b567aeee903e31925b6899f'
assert sha(pkg/'protocol.json')=='2575b0fcdafcf5befb38c4e6a431f856a202164c81763a3eb99e1c141d6055cc'
assert sha(root/'formal_attempt_002/HALT.json')=='42e23aba58d177c2e1a58cc03a4e2ef49dc38d91e4427e600292a340a2883557'
p=json.loads((pkg/'protocol.json').read_text());cell=p['cells'][4]
assert cell['exp_id']==out.name and cell['lambda_upd']==0 and cell['alpha_hf']==2 and cell['seed']==43
start=read('started.json');initial=read('initialization_check.json');resolved=read('resolved_config.json');failure=read('failure.json')
assert start['cell']==cell and start['job_id']=='227699' and start['array_identity']=='227626_4'
assert start['package_manifest_sha256']==sha(pkg/'manifest.json') and start['protocol_sha256']==sha(pkg/'protocol.json')
assert start['initial_weight_tensor_sha256']==initial['frozen_tensor_sha256']==p['frozen_initial_weights']['43']['tensor_sha256']
assert initial['loaded_frozen_tensors_before_any_optimizer_step'] is True
assert resolved['config']['loss']['lambda_upd']==cell['lambda_upd'] and resolved['config']['loss']['alpha_hf']==cell['alpha_hf']
assert resolved['protocol_sha256']==sha(pkg/'protocol.json')
assert failure['state']=='FAILED_REQUIRES_REVIEW' and failure['job_id']=='227699'
assert failure['cell']==cell and failure['type']=='RuntimeError' and failure['message']=='Frozen total numerical-recovery limit exceeded'
assert not (out/'completion.json').exists()
events=[json.loads(line) for line in (out/'events.jsonl').open(encoding='utf-8')]
epochs=[e for e in events if e.get('event')=='epoch_complete']
updates=[e for e in events if e.get('event')=='FIRST_OPTIMIZER_UPDATE_VERIFIED']
replays=[e for e in events if e.get('event')=='FULL_EPOCH_REPLAY_REQUIRED']
assert [e['epoch'] for e in epochs]==list(range(11))
assert len(updates)==1 and updates[0]['before_tensor_sha256']==start['initial_weight_tensor_sha256'] and updates[0]['after_tensor_sha256']!=updates[0]['before_tensor_sha256']
assert len(replays)==4 and [e['recovery_total'] for e in replays]==[1,2,3,4]
assert all(e['epoch']==11 for e in replays)
assert p['numerical_recovery']['max_total_replays_per_cell']==3
expected_train=p['data']['train']['rows']-resolved['config']['data']['window_size']+1
expected_val=p['data']['val']['rows']-resolved['config']['data']['window_size']+1
assert all(e['validation_samples']==expected_val for e in epochs)
train=defaultdict(int)
for e in events:
    if e.get('event')=='training_batch':train[(e['epoch'],e['attempt'])]+=e['samples']
assert all(train[(e['epoch'],0)]==expected_train for e in epochs)
best=min(epochs,key=lambda e:e['common_validation_mse'])
checkpoint=out/('checkpoint_epoch_%03d.pt'%best['epoch'])
assert checkpoint.exists()
print(json.dumps({'state':'FOURTH_CELL_FAILURE_INDEPENDENTLY_AUDITED','array_identity':start['array_identity'],'job_id':start['job_id'],'failure_sha256':sha(out/'failure.json'),'events_sha256':sha(out/'events.jsonl'),'completed_epochs':len(epochs),'first_optimizer_update_verified':True,'recovery_total':len(replays),'recovery_epochs':[e['epoch'] for e in replays],'recovery_attempts':[e['attempt'] for e in replays],'last_completed_epoch_zero_based':epochs[-1]['epoch'],'last_validation_mse':epochs[-1]['common_validation_mse'],'best_completed_epoch_zero_based':best['epoch'],'best_validation_mse_before_failure':best['common_validation_mse'],'best_checkpoint_sha256':sha(checkpoint),'full_training_samples_each_completed_epoch':expected_train,'validation_samples_each_completed_epoch':expected_val,'completion_file_exists':False,'test_data_read':False,'source_manifest_sha256':sha(pkg/'manifest.json'),'old_failure_preserved':True}))
print('REPLAY_EVENTS')
for e in replays: print(json.dumps(e))
print('EVENT_TYPES',json.dumps(Counter(e.get('event') for e in events)))
print('FAILURE_TRACEBACK_TAIL')
print('\n'.join(failure['traceback'].splitlines()[-12:]))
for name in ('weights-227626_4.out','weights-227626_4.err'):
    path=logs/name
    print('LOG_FILE',json.dumps({'name':name,'exists':path.exists(),'bytes':path.stat().st_size if path.exists() else None,'sha256':sha(path) if path.exists() else None}))
    if path.exists():print('LOG_TAIL',name,'\n'.join(path.read_text(errors='replace').splitlines()[-16:]))
PY
printf '\nREAD_ONLY_FAILURE_AUDIT_COMPLETE\n'
