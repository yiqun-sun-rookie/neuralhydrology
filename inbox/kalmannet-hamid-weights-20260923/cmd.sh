#!/bin/bash
set -eo pipefail
sequence=30
root=/data1/home/sunyiq/kalmannet_hamid_weights_20260923_v1
date -u '+SNAPSHOT_UTC=%Y-%m-%dT%H:%M:%SZ'
printf '\nARRAY_QUEUE\n'
squeue -h -j 227626 -o '%i|%j|%T|%P|%R' || true
printf '\nARRAY_ACCOUNTING\n'
sacct -X -j 227626 -n -P --format=JobIDRaw,State,ExitCode,Elapsed,NodeList || true
printf '\nFROZEN_CELL_RECORDS\n'
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY'
import hashlib,json,time
from pathlib import Path
root=Path('/data1/home/sunyiq/kalmannet_hamid_weights_20260923_v1')
pkg=root/'formal_package_v3';attempt=root/'formal_attempt_003'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
assert sha(pkg/'manifest.json')=='4bd8fe167bb5d6932a25161e9855bfdf03f656352b567aeee903e31925b6899f'
assert sha(pkg/'protocol.json')=='2575b0fcdafcf5befb38c4e6a431f856a202164c81763a3eb99e1c141d6055cc'
assert sha(root/'formal_attempt_002/HALT.json')=='42e23aba58d177c2e1a58cc03a4e2ef49dc38d91e4427e600292a340a2883557'
protocol=json.loads((pkg/'protocol.json').read_text())
assert len(protocol['cells'])==12
print(json.dumps({'state':'INPUT_IDENTITIES_VERIFIED','package_manifest_sha256':sha(pkg/'manifest.json'),'protocol_sha256':sha(pkg/'protocol.json'),'old_failure_preserved':True}))
for index in range(1,12):
    cell=protocol['cells'][index];out=attempt/'runs'/cell['exp_id']
    record={'index':index,'exp_id':cell['exp_id'],'lambda_upd':cell['lambda_upd'],'alpha_hf':cell['alpha_hf'],'seed':cell['seed'],'run_dir_exists':out.exists()}
    if out.exists():
        for name in ('started','initialization_check','completion','failure'):
            path=out/(name+'.json')
            if path.exists():
                value=json.loads(path.read_text())
                if name=='started':
                    assert value['cell']==cell and value['protocol_sha256']==sha(pkg/'protocol.json') and value['package_manifest_sha256']==sha(pkg/'manifest.json')
                    assert value['initial_weight_tensor_sha256']==protocol['frozen_initial_weights'][str(cell['seed'])]['tensor_sha256']
                    record['started_job_id']=value['job_id'];record['started_gpu']=value['gpu']
                elif name=='initialization_check':
                    record['frozen_initial_weights_loaded']=value['loaded_frozen_tensors_before_any_optimizer_step']
                    record['frozen_tensor_sha256']=value['frozen_tensor_sha256']
                elif name=='completion':
                    record['completion_state']=value['state'];record['epochs_completed']=value['epochs_completed'];record['best_validation_mse']=value['best_validation_mse'];record['best_epoch']=value['best_epoch'];record['test_data_read']=value['test_data_read']
                    checkpoint=out/value['best_checkpoint'];record['checkpoint_hash_matches']=sha(checkpoint)==value['best_checkpoint_sha256']
                else:
                    record['failure_type']=value['type'];record['failure_message']=value['message'][:250]
        events=out/'events.jsonl'
        if events.exists():
            record['events_bytes']=events.stat().st_size;record['events_mtime_utc']=time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime(events.stat().st_mtime))
            for line in events.open(encoding='utf-8'):
                try:event=json.loads(line)
                except json.JSONDecodeError:continue
                kind=event.get('event')
                if kind=='FIRST_OPTIMIZER_UPDATE_VERIFIED':record['first_optimizer_update_verified']=True
                if kind=='training_batch':record['last_training_batch']={'epoch':event['epoch'],'attempt':event['attempt'],'batch':event['batch'],'samples':event['samples']}
                if kind=='epoch_complete':record['last_complete_epoch']={'epoch':event['epoch'],'common_validation_mse':event['common_validation_mse'],'recovery_total':event['recovery_total'],'peak_gpu_allocated_bytes':event['peak_gpu_allocated_bytes']}
                if kind=='FULL_EPOCH_REPLAY_REQUIRED':record['last_recovery']={'epoch':event['epoch'],'recovery_total':event['recovery_total'],'cause':event['cause'][:150]}
    print(json.dumps(record,allow_nan=False))
PY
printf '\nPROTECTED_OTHER_JOBS\n'
squeue -u sunyiq -h -o '%i|%j|%T|%P|%R'
printf '\nREAD_ONLY_HAMID_CHECK_COMPLETE\n'
