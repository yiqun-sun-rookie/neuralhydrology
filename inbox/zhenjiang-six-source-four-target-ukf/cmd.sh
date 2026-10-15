#!/usr/bin/env bash
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
python -B - <<'PY'
import datetime,hashlib,io,json,pathlib,tarfile
inbox=pathlib.Path('inbox/zhenjiang-six-source-four-target-ukf');sequence=int((inbox/'seq').read_text());assert sequence==500
raw=(inbox/f'payload_complete_comparison_20261006_{sequence}.tar.gz').read_bytes();assert hashlib.sha256(raw).hexdigest()=='cd47c41a4405d8a9ef7b544cf57f82a5b0555297cddce9a6ea2f27ac52751e49'
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_validation_joseph_factorization_audit_20261016_001');assert not root.exists(),'existing isolated deployment requires read-only reconciliation, never overwrite or repeat'
with tarfile.open(fileobj=io.BytesIO(raw),mode='r:gz') as archive:
 members=archive.getmembers();assert members and all(m.isfile() for m in members);assert len(members)==6
 for m in members:
  relative=pathlib.PurePosixPath(m.name);assert not relative.is_absolute() and '..' not in relative.parts and root in (root/m.name).resolve().parents
 content={m.name:archive.extractfile(m).read() for m in members}
manifest=json.loads(content['package_manifest.json']);assert set(content)==set(manifest['files'])|{'package_manifest.json'}
for name,item in manifest['files'].items():assert len(content[name])==item['bytes'] and hashlib.sha256(content[name]).hexdigest()==item['sha256']
spec=json.loads(content['diagnostic_spec.json']);assert spec['schema']=='isolated_saved_positive_joseph_gpu_factorization_audit_v1'
assert spec['source_job']=='242937' and spec['source_code_hash']=='91ad29057526ba7c6c503aa4c8b9e932e6d9a29044bb31e989afd22212a2c1d4'
assert spec['maximum_replay_epochs']==0 and spec['training_data_values_read'] is False and spec['selection_data_values_read'] is False
assert spec['formal_checkpoint_write_allowed'] is False and spec['evaluation_values_read'] is False and spec['scientific_rules_changed'] is False
source=pathlib.Path(spec['source_root'])
for rid,files in spec['all_member_source_files'].items():
 for name,item in files.items():
  p=source/'runs'/rid/name;b=p.read_bytes();assert len(b)==item['bytes'] and hashlib.sha256(b).hexdigest()==item['sha256']
for name,expected in spec['source_code_file_hashes'].items():assert hashlib.sha256((source/name).read_bytes()).hexdigest()==expected
root.mkdir(exist_ok=False)
for name,b in content.items():
 p=root/name;p.parent.mkdir(parents=True,exist_ok=True)
 with p.open('xb') as f:f.write(b)
for name in ['records','logs']:(root/name).mkdir(exist_ok=True)
print(json.dumps({'status':'joseph_factor_gpu_audit_deployed','checked_at_beijing':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),'diagnostic_root':str(root),'source_failed_job':'242937','payload_sha256':hashlib.sha256(raw).hexdigest(),'manifest_sha256':hashlib.sha256(content['package_manifest.json']).hexdigest(),'formal_training_restarted':False,'formal_epochs_added':0,'evaluation_values_read':False},sort_keys=True))
PY
python -B /data1/home/sunyiq/zhenjiang_validation_joseph_factorization_audit_20261016_001/hpc/submit_covariance_diagnostic.py
python -B /data1/home/sunyiq/zhenjiang_validation_joseph_factorization_audit_20261016_001/hpc/probe_covariance_diagnostic.py
