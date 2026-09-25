#!/bin/bash
set -eo pipefail
sequence=43
root=/data1/home/sunyiq/kalmannet_hamid_weights_20260923_v1
date -u '+SNAPSHOT_UTC=%Y-%m-%dT%H:%M:%SZ'
printf '\nSEVENTH_CELL_SCHEDULER_AND_RESOURCE\n'
sacct -X -j 227732 -n -P --format=JobIDRaw,JobName,State,ExitCode,Elapsed,NodeList || true
sstat -j 227732.batch -n -P --format=JobID,MaxRSS,AveCPU || true
printf '\nSEVENTH_CELL_READ_ONLY_PROGRESS_AUDIT\n'
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY'
import hashlib,json
from collections import defaultdict
from pathlib import Path
root=Path('/data1/home/sunyiq/kalmannet_hamid_weights_20260923_v1')
pkg=root/'formal_package_v3'
out=root/'formal_attempt_003/runs/objective-current-0p05-highflow-1-seed-43'
logs=root/'formal_attempt_003/logs'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
assert sha(pkg/'manifest.json')=='4bd8fe167bb5d6932a25161e9855bfdf03f656352b567aeee903e31925b6899f'
assert sha(pkg/'protocol.json')=='2575b0fcdafcf5befb38c4e6a431f856a202164c81763a3eb99e1c141d6055cc'
assert sha(root/'formal_attempt_002/HALT.json')=='42e23aba58d177c2e1a58cc03a4e2ef49dc38d91e4427e600292a340a2883557'
p=json.loads((pkg/'protocol.json').read_text());cell=p['cells'][7]
start=json.loads((out/'started.json').read_text());initial=json.loads((out/'initialization_check.json').read_text());resolved=json.loads((out/'resolved_config.json').read_text())
assert start['cell']==cell and start['job_id']=='227732' and start['array_identity']=='227626_7'
assert start['package_manifest_sha256']==sha(pkg/'manifest.json') and start['protocol_sha256']==sha(pkg/'protocol.json')
assert start['initial_weight_tensor_sha256']==initial['frozen_tensor_sha256']==p['frozen_initial_weights']['43']['tensor_sha256']
assert initial['loaded_frozen_tensors_before_any_optimizer_step'] is True
assert resolved['config']['loss']['lambda_upd']==cell['lambda_upd']==0.05 and resolved['config']['loss']['alpha_hf']==cell['alpha_hf']==1
events=[]
for line in (out/'events.jsonl').open(encoding='utf-8'):
    try:events.append(json.loads(line))
    except json.JSONDecodeError:continue
epochs=[e for e in events if e.get('event')=='epoch_complete']
updates=[e for e in events if e.get('event')=='FIRST_OPTIMIZER_UPDATE_VERIFIED']
replays=[e for e in events if e.get('event')=='FULL_EPOCH_REPLAY_REQUIRED']
assert len(epochs)>=21 and [e['epoch'] for e in epochs]==list(range(len(epochs)))
assert len(updates)==1 and updates[0]['before_tensor_sha256']==start['initial_weight_tensor_sha256'] and updates[0]['after_tensor_sha256']!=updates[0]['before_tensor_sha256']
assert len(replays)<=3
expected_train=p['data']['train']['rows']-resolved['config']['data']['window_size']+1
expected_val=p['data']['val']['rows']-resolved['config']['data']['window_size']+1
assert all(e['validation_samples']==expected_val for e in epochs)
train=defaultdict(int)
for e in events:
    if e.get('event')=='training_batch':train[(e['epoch'],e['attempt'])]+=e['samples']
for e in epochs:
    attempt=max(a for n,a in train if n==e['epoch'])
    assert train[(e['epoch'],attempt)]==expected_train
print(json.dumps({'state':'SEVENTH_CELL_RUNNING_PROGRESS_INDEPENDENTLY_CHECKED','array_identity':start['array_identity'],'job_id':start['job_id'],'completed_epochs':len(epochs),'first_optimizer_update_verified':True,'recovery_total_observed':len(replays),'recovery_epochs':[e['epoch'] for e in replays],'last_completed_epoch_zero_based':epochs[-1]['epoch'],'last_validation_mse':epochs[-1]['common_validation_mse'],'last_epoch_peak_gpu_allocated_bytes':epochs[-1]['peak_gpu_allocated_bytes'],'completion_file_exists':(out/'completion.json').exists(),'failure_file_exists':(out/'failure.json').exists(),'test_data_read':False,'old_failure_preserved':True}))
for name in ('weights-227626_7.out','weights-227626_7.err'):
    path=logs/name
    print('LOG_FILE',json.dumps({'name':name,'exists':path.exists(),'bytes':path.stat().st_size if path.exists() else None}))
    if path.exists():print('LOG_TAIL',name,'\n'.join(path.read_text(errors='replace').splitlines()[-5:]))
PY
printf '\nREAD_ONLY_PROGRESS_AUDIT_COMPLETE\n'
