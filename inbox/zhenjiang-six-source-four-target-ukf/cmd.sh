#!/usr/bin/env bash
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
python -B - <<'PY'
"""CPU audit of complete member histories, parameters, Adam and source identity.

No model or data loader runs. Source failures and all old artifacts stay intact.
Run before every scheduler continuation; each immutable audit is retained.
"""
import datetime
import hashlib
import json
from pathlib import Path

import torch
import sys
sys.path.insert(0,'/data1/home/sunyiq/zhenjiang_complete_comparison_20261015_recovery_004/hpc')

import prepare_covariance_recovery_20261015 as h

ROOT = Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261015_recovery_004')
CASE = 'explicit_gru__historical_capacity'


def tensor_list(value):
    if isinstance(value, torch.Tensor):
        return [value]
    if isinstance(value, dict):
        return sum([tensor_list(value[k]) for k in sorted(value, key=repr)], [])
    if isinstance(value, (list, tuple)):
        return sum([tensor_list(x) for x in value], [])
    return []


def main():
    prep = h.read(ROOT/'records/recovery_preparation_complete.json')
    intent = h.read(ROOT/'records/covariance_recovery_intent_20261015.json')
    auth = h.read(ROOT/'records/authorization.json')
    assert h.code_identity() == auth['code_hash'] == prep['recovery_code_hash']
    assert h.sha(ROOT/'configs/protocol-v3.json') == auth['protocol_sha256']
    assert h.code_identity(h.PARENT) == intent['source_code_hash']
    assert all(h.sha(Path(p)) == digest for p, digest in intent['pinned_source_files'].items())
    assert str(h.read(ROOT/'records/scheduler_jobs.json')[CASE])=='242609'
    import subprocess
    q=subprocess.run(['squeue','-h','-j','242609','-o','%i|%T'],capture_output=True,text=True,check=True)
    assert not q.stdout.strip(), 'failed source still active'
    rows = []
    for m in prep['migrations']:
        source = Path(m['source_root'])/'runs'/m['run']
        target = ROOT/'runs'/m['run']
        assert all(h.sha(source/name) == expected for name, expected in m['source_files'].items())
        old = torch.load(source/'continuation.pt', map_location='cpu', weights_only=True)
        raw = (target/'continuation.pt').read_bytes()
        import io
        new = torch.load(io.BytesIO(raw), map_location='cpu', weights_only=True)
        h.finite(new)
        n, count = len(old['values']), len(new['values'])
        assert count >= n and n == m['epochs_preserved']
        assert all(new[k][:n] == old[k] and len(new[k]) == count for k in ('values', 'train_metrics', 'shuffle_hashes'))
        assert new['config_sha256'] == m['recovery_config_sha256'] == h.sha(target/'config.json')
        before = [float(s['step']) for s in old['optimizer']['state'].values()]
        after = [float(s['step']) for s in new['optimizer']['state'].values()]
        assert len(before) == len(after) and min(b-a for a, b in zip(before, after)) >= 0
        changed = any(not torch.equal(a, b) for a, b in zip(tensor_list(old['current']), tensor_list(new['current'])))
        if count > n:
            assert changed and min(b-a for a, b in zip(before, after)) > 0
        else:
            assert h.state_hash({k:v for k,v in new.items() if k != 'config_sha256'}) == m['training_state_semantic_sha256']
        failure_path=target/'failure.json'
        failure=h.read(failure_path)
        assert failure['status']=='failed' and failure['reason']=='invalid covariance'
        assert failure['evidence']['shape']==[16,128,128] and failure['epochs_completed']==count
        rows.append({'run':m['run'], 'source_epochs':n, 'current_saved_epochs':count,
                     'added_complete_epochs':count-n, 'minimum_added_optimizer_steps':min(b-a for a,b in zip(before,after)),
                     'current_parameters_differ':changed, 'current_checkpoint_sha256':hashlib.sha256(raw).hexdigest(),
                     'checkpoint_bytes':len(raw), 'source_files_unchanged':True, 'all_source_histories_preserved':True,
                     'configuration_binding_verified':True, 'all_saved_tensors_finite':True, 'failure':failure, 'failure_sha256':h.sha(failure_path)})
        del old, new, raw
    at = datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8)))
    jobs_path = ROOT/'records/scheduler_jobs.json'
    jobs = h.read(jobs_path) if jobs_path.exists() else {}
    audit = {'status':'covariance_failed_checkpoint_audit_preserved', 'checked_at_beijing':at.isoformat(),
             'case':CASE, 'root':str(ROOT), 'job_id':jobs.get(CASE), 'members':rows,
             'additional_complete_member_epochs':sum(x['added_complete_epochs'] for x in rows),
             'code_hash':auth['code_hash'], 'source_code_hash':intent['source_code_hash'],
             'all_source_bytes_unchanged':True, 'any_new_failure_file':True, 'continuation_admitted':False,
             'scientific_protocol_unchanged':True, 'training_or_checkpoint_files_written':False,
             'evaluation_values_read':False}
    path = ROOT/'records'/('covariance_failed_checkpoint_audit_'+at.strftime('%Y%m%d_%H%M%S_%f')+'.json')
    h.write(path, audit)
    latest = ROOT/'records/covariance_failed_checkpoint_audit_latest.json'
    temporary = latest.with_name(latest.name+'.tmp')
    h.write(temporary, dict(audit, immutable_record=str(path), immutable_record_sha256=h.sha(path)))
    temporary.replace(latest)
    print(json.dumps(audit, sort_keys=True), flush=True)


if __name__ == '__main__':
    main()

PY
