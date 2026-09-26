#!/bin/bash
set -eo pipefail
sequence=49
root=/data1/home/sunyiq/kalmannet_hamid_weights_20260923_v1
date -u '+SNAPSHOT_UTC=%Y-%m-%dT%H:%M:%SZ'
printf '\nRELATED_JOB_ACCOUNTING\n'
sacct -X -j 227745,227748,227749 -n -P --format=JobIDRaw,JobName,State,ExitCode,Elapsed,NodeList || true
printf '\nEIGHTH_AND_NINTH_COMPLETED_CELLS_INDEPENDENT_AUDIT\n'
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY'
import hashlib,json
from collections import defaultdict
from pathlib import Path
root=Path('/data1/home/sunyiq/kalmannet_hamid_weights_20260923_v1')
pkg=root/'formal_package_v3'
attempt=root/'formal_attempt_003'
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
assert sha(pkg/'manifest.json')=='4bd8fe167bb5d6932a25161e9855bfdf03f656352b567aeee903e31925b6899f'
assert sha(pkg/'protocol.json')=='2575b0fcdafcf5befb38c4e6a431f856a202164c81763a3eb99e1c141d6055cc'
assert sha(root/'formal_attempt_002/HALT.json')=='42e23aba58d177c2e1a58cc03a4e2ef49dc38d91e4427e600292a340a2883557'
protocol=json.loads((pkg/'protocol.json').read_text())
checks={
  8:('227745',0.05,1,44,33,22,1,9.625192447391192e-06),
  9:('227748',0,1,42,16,5,2,1.0419680334440512e-05),
}
for index,(job,lam,alpha,seed,epoch_count,best_epoch,replay_count,best_mse) in checks.items():
    cell=protocol['cells'][index]
    out=attempt/'runs'/cell['exp_id']
    def read(name):return json.loads((out/name).read_text())
    assert cell['lambda_upd']==lam and cell['alpha_hf']==alpha and cell['seed']==seed
    start=read('started.json');initial=read('initialization_check.json');complete=read('completion.json');resolved=read('resolved_config.json')
    assert start['cell']==cell and start['job_id']==job and start['array_identity']==f'227626_{index}'
    assert start['package_manifest_sha256']==sha(pkg/'manifest.json') and start['protocol_sha256']==sha(pkg/'protocol.json')
    assert start['initial_weight_tensor_sha256']==initial['frozen_tensor_sha256']==protocol['frozen_initial_weights'][str(seed)]['tensor_sha256']
    assert initial['loaded_frozen_tensors_before_any_optimizer_step'] is True
    assert resolved['config']['loss']['lambda_upd']==lam and resolved['config']['loss']['alpha_hf']==alpha
    assert resolved['protocol_sha256']==sha(pkg/'protocol.json')
    assert complete['state']=='TRAINING_COMPLETE_NOT_SCIENTIFIC_EVALUATION' and complete['test_data_read'] is False
    assert not (out/'failure.json').exists()
    events=[json.loads(line) for line in (out/'events.jsonl').open(encoding='utf-8')]
    epochs=[e for e in events if e.get('event')=='epoch_complete']
    updates=[e for e in events if e.get('event')=='FIRST_OPTIMIZER_UPDATE_VERIFIED']
    replays=[e for e in events if e.get('event')=='FULL_EPOCH_REPLAY_REQUIRED']
    assert len(epochs)==complete['epochs_completed']==epoch_count and [e['epoch'] for e in epochs]==list(range(epoch_count))
    assert len(updates)==1 and updates[0]['before_tensor_sha256']==start['initial_weight_tensor_sha256'] and updates[0]['after_tensor_sha256']!=updates[0]['before_tensor_sha256']
    assert len(replays)==complete['recovery_total']==replay_count and [e['recovery_total'] for e in replays]==list(range(1,replay_count+1))
    assert all(e['epoch'] in range(epoch_count) for e in replays)
    best=min(epochs,key=lambda e:e['common_validation_mse'])
    assert best['epoch']==complete['best_epoch']==best_epoch and best['common_validation_mse']==complete['best_validation_mse']==best_mse
    assert complete['best_checkpoint']==f'checkpoint_epoch_{best_epoch:03d}.pt'
    assert sha(out/complete['best_checkpoint'])==complete['best_checkpoint_sha256']
    expected_train=protocol['data']['train']['rows']-resolved['config']['data']['window_size']+1
    expected_val=protocol['data']['val']['rows']-resolved['config']['data']['window_size']+1
    assert all(e['validation_samples']==expected_val for e in epochs)
    train=defaultdict(int)
    for e in events:
        if e.get('event')=='training_batch':train[(e['epoch'],e['attempt'])]+=e['samples']
    for e in epochs:
        attempt_number=max(a for n,a in train if n==e['epoch'])
        assert train[(e['epoch'],attempt_number)]==expected_train
    print(json.dumps({'state':'CELL_TRAINING_INDEPENDENTLY_AUDITED','index':index,'array_identity':start['array_identity'],'job_id':job,'epochs_completed':epoch_count,'first_optimizer_update_verified':True,'recovery_total':replay_count,'recovery_epochs':[e['epoch'] for e in replays],'best_epoch_zero_based':best_epoch,'best_validation_mse':best_mse,'checkpoint_sha256':complete['best_checkpoint_sha256'],'validation_samples_each_epoch':expected_val,'full_training_samples_each_completed_epoch':expected_train,'last_epoch_peak_gpu_allocated_bytes':epochs[-1]['peak_gpu_allocated_bytes'],'test_data_read':False,'scientific_comparison_complete':False,'old_failure_preserved':True}))
    for suffix in ('out','err'):
        name=f'weights-227626_{index}.{suffix}';path=attempt/'logs'/name
        print('LOG_FILE',json.dumps({'name':name,'exists':path.exists(),'bytes':path.stat().st_size if path.exists() else None,'sha256':sha(path) if path.exists() else None}))
        if path.exists():print('LOG_TAIL',name,'\n'.join(path.read_text(errors='replace').splitlines()[-4:]))
PY
printf '\nREAD_ONLY_AUDIT_COMPLETE\n'
