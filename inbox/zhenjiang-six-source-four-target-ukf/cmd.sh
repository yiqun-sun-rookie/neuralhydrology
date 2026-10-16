#!/usr/bin/env bash
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
python -B - <<'PY'
import datetime,hashlib,io,json,pathlib,subprocess,tarfile
inbox=pathlib.Path('inbox/zhenjiang-six-source-four-target-ukf');sequence=int((inbox/'seq').read_text());assert sequence==526
raw=(inbox/f'payload_complete_comparison_20261006_{sequence}.tar.gz').read_bytes();assert hashlib.sha256(raw).hexdigest()=='2d984d4755e67c1b03b48a565478fc91ceda6060c6c1506c8e096fbf62a100d7'
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_validation_compensated_cholesky_20261016_002');assert not root.exists(),'existing deployment requires read-only reconciliation, never retry'
with tarfile.open(fileobj=io.BytesIO(raw),mode='r:gz') as archive:
 members=archive.getmembers();assert len(members)==9 and all(m.isfile() for m in members)
 for m in members:
  p=pathlib.PurePosixPath(m.name);assert not p.is_absolute() and '..' not in p.parts
 content={m.name:archive.extractfile(m).read() for m in members}
manifest=json.loads(content['package_manifest.json']);assert set(content)==set(manifest['files'])|{'package_manifest.json'}
for name,item in manifest['files'].items():assert len(content[name])==item['bytes'] and hashlib.sha256(content[name]).hexdigest()==item['sha256']
spec=json.loads(content['diagnostic_spec.json']);assert spec['schema']=='isolated_original2021_compensated_cholesky_validation_v1'
assert spec['diagnostic_root']==str(root) and spec['maximum_replay_epochs']==1 and spec['formal_checkpoint_write_allowed'] is False
assert spec['expected_saved_epoch']==45 and spec['expected_optimizer_steps']==6906 and spec['replayed_epoch']==46
assert spec['in_memory_optimizer_replay_allowed'] and spec['validation_input_read_allowed'] and spec['selection_years']==[2021]
assert spec['training_years']==[2017,2018,2019,2020] and spec['evaluation_values_read'] is False and spec['scientific_rules_changed'] is False
def verify_prior_technical_failure(spec):
    prior=spec['prior_technical_failure']
    path=pathlib.Path(prior['result_path'])
    assert hashlib.sha256(path.read_bytes()).hexdigest()==prior['result_sha256']
    value=json.loads(path.read_bytes())
    assert value['exception_type']=='FileExistsError' and not value['covariance_failure_observed']
    assert value['source_bytes_unchanged'] and value['source_code_unchanged']
    assert value['formal_training_epochs_added']==0
    for key,expected in [('original_validation_stability_ledger','ledger_sha256'),('before_validation_model_adam_rng','batch_start_sha256')]:
        assert hashlib.sha256(pathlib.Path(value[key]['path']).read_bytes()).hexdigest()==prior[expected]
    accounting=subprocess.run(['sacct','-n','-X','-j',prior['job_id'],'--format=JobID,State,ExitCode,Start,End','-P'],capture_output=True,text=True,check=True,timeout=30)
    rows=[line.split('|') for line in accounting.stdout.splitlines() if line.startswith(prior['job_id']+'|')]
    assert len(rows)==1 and rows[0][:5]==[prior['job_id'],'COMPLETED','0:0',prior['actual_start'],prior['actual_end']]
    return rows[0]

verify_prior_technical_failure(spec)
source=pathlib.Path(spec['source_root']);assert len(spec['pinned_source_files'])==58 and len(spec['source_code_file_hashes'])==37
for name,expected in spec['pinned_source_files'].items():assert hashlib.sha256(pathlib.Path(name).read_bytes()).hexdigest()==expected
for name,expected in spec['source_code_file_hashes'].items():assert hashlib.sha256((source/name).read_bytes()).hexdigest()==expected
for name,expected in spec['bootstrap_test_sha256'].items():assert hashlib.sha256((source/name).read_bytes()).hexdigest()==expected
parent=pathlib.Path(spec['parent_gate_result_path']);assert hashlib.sha256(parent.read_bytes()).hexdigest()==spec['parent_gate_result_sha256']
proof=json.loads(parent.read_bytes());assert proof['saved_matrix_gate_passed'] and proof['gradient_gate_passed'] and proof['formal_repair_admitted'] is False
acct=subprocess.run(['sacct','-n','-X','-j',spec['parent_gate_job'],'--format=JobID,State,ExitCode,Start,End','-P'],capture_output=True,text=True,check=True,timeout=30)
rows=[l.split('|') for l in acct.stdout.splitlines() if l.startswith(spec['parent_gate_job']+'|')]
assert len(rows)==1 and rows[0][:5]==[spec['parent_gate_job'],'COMPLETED','0:0',spec['parent_gate_actual_start'],spec['parent_gate_actual_end']]
queue=subprocess.run(['squeue','-h','-u','sunyiq','-o','%i|%j|%T|%Z'],capture_output=True,text=True,check=True,timeout=30)
assert not any(l.split('|')[1].startswith('zj_gru_') or l.split('|')[3] in (str(root),str(source)) for l in queue.stdout.splitlines() if l.strip()),'source or matching diagnostic is active'
root.mkdir(exist_ok=False)
for name,b in content.items():
 p=root/name;p.parent.mkdir(parents=True,exist_ok=True)
 with p.open('xb') as f:f.write(b)
for name in ['records','logs']:(root/name).mkdir(exist_ok=True)
print(json.dumps({'status':'compensated_validation_ledgerfix_deployed','checked_at_beijing':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),'diagnostic_root':str(root),'source_failed_job':'242937','payload_sha256':hashlib.sha256(raw).hexdigest(),'manifest_sha256':hashlib.sha256(content['package_manifest.json']).hexdigest(),'parent_actual_accounting':rows[0],'formal_training_restarted':False,'formal_epochs_added':0,'evaluation_values_read':False},sort_keys=True))
PY
python -B /data1/home/sunyiq/zhenjiang_validation_compensated_cholesky_20261016_002/hpc/submit_covariance_diagnostic.py
python -B /data1/home/sunyiq/zhenjiang_validation_compensated_cholesky_20261016_002/hpc/probe_covariance_diagnostic.py
