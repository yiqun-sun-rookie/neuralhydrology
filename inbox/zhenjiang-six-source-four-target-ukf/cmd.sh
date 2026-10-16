#!/usr/bin/env bash
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
export CUDA_VISIBLE_DEVICES=""
export OMP_NUM_THREADS=4
export MKL_NUM_THREADS=4
python -B - <<'PYDEPLOY'
import datetime,hashlib,io,json,pathlib,tarfile
inbox=pathlib.Path('inbox/zhenjiang-six-source-four-target-ukf');sequence=int((inbox/'seq').read_text());assert sequence==529
raw=(inbox/f'payload_complete_comparison_20261006_{sequence}.tar.gz').read_bytes();assert hashlib.sha256(raw).hexdigest()=='ff8ac85963defc70180d4fdec6be2338febbcda3fe980d0e2eff4805c5afabcf'
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261016_recovery_006');assert not root.exists(),'existing release must be reconciled read-only; never overwrite or repeat deployment'
with tarfile.open(fileobj=io.BytesIO(raw),mode='r:gz') as archive:
 members=archive.getmembers();assert members and all(m.isfile() for m in members)
 assert len({m.name for m in members})==len(members)
 for m in members:
  relative=pathlib.PurePosixPath(m.name);assert not relative.is_absolute() and '..' not in relative.parts and root in (root/m.name).resolve().parents
 content={m.name:archive.extractfile(m).read() for m in members}
manifest=json.loads(content['release_manifest.json']);assert set(content)==set(manifest['files'])|{'release_manifest.json'}
for name,item in manifest['files'].items():assert len(content[name])==item['bytes'] and hashlib.sha256(content[name]).hexdigest()==item['sha256']
intent=json.loads(content['records/covariance_recovery_intent_20261015.json']);assert intent['recovery_root']==str(root) and intent['source_failed_job']=='242937'
assert intent['recovery_code_hash']==manifest['code_hash']=='4232fbb467341b6332f91e9289cdb975613babb5d29e2079b66d55f7822c3757'
assert all(hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()==h for path,h in intent['pinned_source_files'].items())
root.mkdir(exist_ok=False)
for name,data in content.items():
 path=root/name;path.parent.mkdir(parents=True,exist_ok=True)
 with path.open('xb') as stream:stream.write(data)
for name in ['logs','runs']:(root/name).mkdir(exist_ok=True)
print(json.dumps({'status':'covariance_recovery_release_deployed','checked_at_beijing':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),'root':str(root),'code_hash':manifest['code_hash'],'payload_sha256':hashlib.sha256(raw).hexdigest(),'release_manifest_sha256':hashlib.sha256(content['release_manifest.json']).hexdigest(),'files_authenticated':len(manifest['files']),'formal_training_submitted':False,'evaluation_values_read':False},sort_keys=True),flush=True)
PYDEPLOY
python -B /data1/home/sunyiq/zhenjiang_complete_comparison_20261016_recovery_006/hpc/prepare_compensated_recovery_20261016.py
python -B /data1/home/sunyiq/zhenjiang_complete_comparison_20261016_recovery_006/hpc/audit_compensated_continuation_20261016.py
