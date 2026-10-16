#!/usr/bin/env bash
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
export CUDA_VISIBLE_DEVICES=""
export OMP_NUM_THREADS=4
export MKL_NUM_THREADS=4
python -B - <<'REPAIR530'
import datetime,hashlib,io,json,pathlib,tarfile
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261016_recovery_006')
inbox=pathlib.Path('inbox/zhenjiang-six-source-four-target-ukf');assert int((inbox/'seq').read_text())==530
raw=(inbox/'payload_complete_comparison_20261006_530.tar.gz').read_bytes();assert hashlib.sha256(raw).hexdigest()=='c3ed008cd7d01e2b51b6232c56287434c1f20e93b52629cdc275f123eb854474'
base=root/'release_manifest.json';assert hashlib.sha256(base.read_bytes()).hexdigest()=='2f1e9dfaa051f29228699a7111acf50ce41464586a992650258fa1c16286dd87'
manifest=json.loads(base.read_bytes())
assert all(hashlib.sha256((root/name).read_bytes()).hexdigest()==item['sha256'] for name,item in manifest['files'].items())
assert not list((root/'runs').iterdir())
assert not (root/'records/explicit_gru__historical_capacity').exists()
assert not (root/'records/recovery_preparation_complete.json').exists()
assert not (root/'records/covariance_recovery_cpu_admitted_20261015.json').exists()
assert not (root/'records/scheduler_jobs.json').exists()
assert not list((root/'records').glob('*submission*'))
intent=json.loads((root/'records/covariance_recovery_intent_20261015.json').read_bytes())
assert all(hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()==h for p,h in intent['pinned_source_files'].items())
result=json.loads(pathlib.Path(intent['candidate_result_path']).read_bytes())
assert result['successful_in_memory_batches']==154 and isinstance(result['final_in_memory_optimizer_steps'],list) and set(result['final_in_memory_optimizer_steps'])=={7060.0}
with tarfile.open(fileobj=io.BytesIO(raw)) as tar:
 members=tar.getmembers();assert len(members)==3 and all(m.isfile() and not pathlib.PurePosixPath(m.name).is_absolute() and '..' not in pathlib.PurePosixPath(m.name).parts for m in members)
 content={m.name:tar.extractfile(m).read() for m in members}
patch=json.loads(content['records/formal006_preparation_control_repair_530_manifest.json'])
assert set(content)==set(patch['files'])|{'records/formal006_preparation_control_repair_530_manifest.json'}
for name,item in patch['files'].items():assert hashlib.sha256(content[name]).hexdigest()==item['sha256'] and len(content[name])==item['bytes']
assert all(not (root/name).exists() for name in content)
for name,data in content.items():
 with (root/name).open('xb') as f:f.write(data)
print(json.dumps({'status':'formal006_preparation_control_repair_deployed','checked_at_beijing':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),'root':str(root),'code_hash':manifest['code_hash'],'payload_sha256':hashlib.sha256(raw).hexdigest(),'release_manifest_sha256':hashlib.sha256(base.read_bytes()).hexdigest(),'patch_manifest_sha256':hashlib.sha256(content['records/formal006_preparation_control_repair_530_manifest.json']).hexdigest(),'no_prior_checkpoint_migration_or_submission_verified':True,'frozen_source_unchanged':True,'formal_training_submitted':False,'evaluation_values_read':False},sort_keys=True),flush=True)
REPAIR530
python -B /data1/home/sunyiq/zhenjiang_complete_comparison_20261016_recovery_006/hpc/prepare_compensated_recovery_20261016_v2.py
python -B /data1/home/sunyiq/zhenjiang_complete_comparison_20261016_recovery_006/hpc/audit_compensated_continuation_20261016_v2.py
