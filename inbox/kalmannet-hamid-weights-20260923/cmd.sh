#!/bin/bash
set -eo pipefail
sequence=31
root=/data1/home/sunyiq/kalmannet_hamid_weights_20260923_v1
date -u '+SNAPSHOT_UTC=%Y-%m-%dT%H:%M:%SZ'
printf '\nRELATED_AND_PROTECTED_JOB_ACCOUNTING\n'
sacct -X -j 227627,227671,227612 -n -P --format=JobIDRaw,JobName,State,ExitCode,Elapsed,NodeList || true
printf '\nFIRST_COMPLETED_CELL_INDEPENDENT_AUDIT\n'
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY'
import hashlib,json,math
from collections import defaultdict
from pathlib import Path
root=Path('/data1/home/sunyiq/kalmannet_hamid_weights_20260923_v1')
pkg=root/'formal_package_v3'
out=root/'formal_attempt_003/runs/objective-current-0p05-highflow-2-seed-43'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(n):return json.loads((out/n).read_text())
assert sha(pkg/'manifest.json')=='4bd8fe167bb5d6932a25161e9855bfdf03f656352b567aeee903e31925b6899f'
assert sha(pkg/'protocol.json')=='2575b0fcdafcf5befb38c4e6a431f856a202164c81763a3eb99e1c141d6055cc'
protocol=json.loads((pkg/'protocol.json').read_text())
cell=protocol['cells'][1]
assert cell['exp_id']==out.name
start=read('started.json');initial=read('initialization_check.json');complete=read('completion.json');resolved=read('resolved_config.json')
assert start['cell']==cell and start['job_id']=='227627' and start['array_identity']=='227626_1'
assert start['package_manifest_sha256']==sha(pkg/'manifest.json') and start['protocol_sha256']==sha(pkg/'protocol.json')
assert start['initial_weight_tensor_sha256']==initial['frozen_tensor_sha256']==protocol['frozen_initial_weights']['43']['tensor_sha256']
assert initial['loaded_frozen_tensors_before_any_optimizer_step'] is True
assert resolved['config']['loss']['lambda_upd']==cell['lambda_upd'] and resolved['config']['loss']['alpha_hf']==cell['alpha_hf']
assert resolved['protocol_sha256']==sha(pkg/'protocol.json')
assert complete['state']=='TRAINING_COMPLETE_NOT_SCIENTIFIC_EVALUATION' and complete['test_data_read'] is False
assert not (out/'failure.json').exists()
events=[json.loads(line) for line in (out/'events.jsonl').open(encoding='utf-8')]
epoch=[e for e in events if e.get('event')=='epoch_complete']
updates=[e for e in events if e.get('event')=='FIRST_OPTIMIZER_UPDATE_VERIFIED']
replays=[e for e in events if e.get('event')=='FULL_EPOCH_REPLAY_REQUIRED']
assert len(epoch)==complete['epochs_completed']==48 and [e['epoch'] for e in epoch]==list(range(48))
assert len(updates)==1 and updates[0]['before_tensor_sha256']==start['initial_weight_tensor_sha256'] and updates[0]['after_tensor_sha256']!=updates[0]['before_tensor_sha256']
assert len(replays)==complete['recovery_total']==1 and replays[0]['epoch']==14
best=min(epoch,key=lambda e:e['common_validation_mse'])
assert best['epoch']==complete['best_epoch']==41 and best['common_validation_mse']==complete['best_validation_mse']
assert complete['best_checkpoint']=='checkpoint_epoch_041.pt'
assert sha(out/complete['best_checkpoint'])==complete['best_checkpoint_sha256']
validation_counts={e['validation_samples'] for e in epoch}
expected_train=protocol['data']['train']['rows']-resolved['config']['data']['window_size']+1
expected_val=protocol['data']['val']['rows']-resolved['config']['data']['window_size']+1
assert len(validation_counts)==1 and next(iter(validation_counts))==expected_val
train=defaultdict(int)
for e in events:
    if e.get('event')=='training_batch':train[(e['epoch'],e['attempt'])]+=e['samples']
assert len(train)>=48
assert all(train[(e['epoch'],1 if e['epoch']==14 else 0)]==expected_train for e in epoch)
print(json.dumps({'state':'FIRST_CELL_TRAINING_INDEPENDENTLY_AUDITED','array_identity':start['array_identity'],'job_id':start['job_id'],'epochs_completed':len(epoch),'first_optimizer_update_verified':True,'recovery_total':len(replays),'best_epoch_zero_based':best['epoch'],'best_validation_mse':best['common_validation_mse'],'checkpoint_sha256':sha(out/complete['best_checkpoint']),'validation_samples_each_epoch':expected_val,'full_training_samples_each_completed_epoch':expected_train,'test_data_read':False,'scientific_comparison_complete':False}))
PY
printf '\nREAD_ONLY_AUDIT_COMPLETE\n'
