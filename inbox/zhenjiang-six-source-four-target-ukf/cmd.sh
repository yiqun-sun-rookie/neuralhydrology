#!/usr/bin/env bash
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
python -B - <<'PY'
import datetime,hashlib,io,json,pathlib,subprocess,tarfile
inbox=pathlib.Path('inbox/zhenjiang-six-source-four-target-ukf');sequence=int((inbox/'seq').read_text());assert sequence==508
raw=(inbox/f'payload_complete_comparison_20261006_{sequence}.tar.gz').read_bytes();assert hashlib.sha256(raw).hexdigest()=='4f161b8860b1bfd1494f6e13e3eb67eef635fb9efd80bc12ef860fd11306e27b'
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_validation_joseph_compensated_factor_20261016_001');assert not root.exists(),'existing isolated deployment requires read-only reconciliation, never retry'
with tarfile.open(fileobj=io.BytesIO(raw),mode='r:gz') as archive:
 members=archive.getmembers();assert len(members)==6 and all(m.isfile() for m in members)
 for m in members:
  rel=pathlib.PurePosixPath(m.name);assert not rel.is_absolute() and '..' not in rel.parts
 content={m.name:archive.extractfile(m).read() for m in members}
manifest=json.loads(content['package_manifest.json']);assert set(content)==set(manifest['files'])|{'package_manifest.json'}
for name,item in manifest['files'].items():assert len(content[name])==item['bytes'] and hashlib.sha256(content[name]).hexdigest()==item['sha256']
spec=json.loads(content['diagnostic_spec.json']);assert spec['schema']=='isolated_saved_float64_compensated_cholesky_gate_v1'
assert spec['diagnostic_root']==str(root) and spec['maximum_replay_epochs']==0 and spec['repair_admitted'] is False
assert spec['formal_checkpoint_write_allowed'] is False and spec['validation_input_read_allowed'] is False
assert spec['training_data_values_read'] is False and spec['selection_data_values_read'] is False and spec['evaluation_values_read'] is False
assert spec['relative_gate']==1e-10 and spec['cpu_reference_digits']==[80,120]
source=pathlib.Path(spec['source_root'])
assert len(spec['pinned_source_files'])==58 and len(spec['source_code_file_hashes'])==37
for name,expected in spec['pinned_source_files'].items():assert hashlib.sha256(pathlib.Path(name).read_bytes()).hexdigest()==expected
for name,expected in spec['source_code_file_hashes'].items():assert hashlib.sha256((source/name).read_bytes()).hexdigest()==expected
assert hashlib.sha256(pathlib.Path(spec['parent_factor_result_path']).read_bytes()).hexdigest()==spec['parent_factor_result_sha256']
parent=json.loads(pathlib.Path(spec['parent_factor_result_path']).read_bytes());assert parent['original_gpu_rejection_reproduced'] and not parent['any_power_two_congruence_factor_passed']
accounting=subprocess.run(['sacct','-n','-X','-j',spec['parent_factor_job'],'--format=JobID,State,ExitCode,Start,End','-P'],capture_output=True,text=True,check=True,timeout=30)
rows=[line.split('|') for line in accounting.stdout.splitlines() if line.startswith(spec['parent_factor_job']+'|')]
assert len(rows)==1 and rows[0][:5]==[spec['parent_factor_job'],'COMPLETED','0:0',spec['parent_factor_actual_start'],spec['parent_factor_actual_end']]
queue=subprocess.run(['squeue','-h','-u','sunyiq','-o','%i|%j|%T|%Z'],capture_output=True,text=True,check=True,timeout=30)
assert not any(line.split('|')[1].startswith('zj_gru_') or line.split('|')[3] in (str(root),str(source)) for line in queue.stdout.splitlines() if line.strip()),'source/diagnostic allocation already active'
root.mkdir(exist_ok=False)
for name,b in content.items():
 p=root/name;p.parent.mkdir(parents=True,exist_ok=True)
 with p.open('xb') as stream:stream.write(b)
for name in ['records','logs']:(root/name).mkdir(exist_ok=True)
print(json.dumps({'status':'compensated_factor_gate_deployed','checked_at_beijing':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),'diagnostic_root':str(root),'source_failed_job':'242937','payload_sha256':hashlib.sha256(raw).hexdigest(),'manifest_sha256':hashlib.sha256(content['package_manifest.json']).hexdigest(),'parent_actual_accounting':rows[0],'formal_training_restarted':False,'formal_epochs_added':0,'evaluation_values_read':False},sort_keys=True))
PY
python -B /data1/home/sunyiq/zhenjiang_validation_joseph_compensated_factor_20261016_001/hpc/submit_covariance_diagnostic.py
python -B /data1/home/sunyiq/zhenjiang_validation_joseph_compensated_factor_20261016_001/hpc/probe_covariance_diagnostic.py
