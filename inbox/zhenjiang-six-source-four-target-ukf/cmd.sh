#!/usr/bin/env bash
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
python -B - <<'PY'
import datetime,hashlib,json,pathlib,subprocess
import mpmath,torch
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_covariance_saved_matrix_audit_20261014_001')
assert root.is_dir() and not (root/'records').exists() and not (root/'evidence').exists()
manifest=json.loads((root/'package_manifest.json').read_text())
assert hashlib.sha256((root/'package_manifest.json').read_bytes()).hexdigest()=='c6ef771acde4ef4f6ae4ba7cafb85a69e22f7c184a3fada1ef666481739a4f61'
for relative,identity in manifest['files'].items():
    path=root/relative
    assert path.is_file() and path.stat().st_size==identity['bytes'] and hashlib.sha256(path.read_bytes()).hexdigest()==identity['sha256']
assert {p.relative_to(root).as_posix() for p in root.rglob('*') if p.is_file()}==set(manifest['files'])|{'package_manifest.json'}
queue=subprocess.run(['squeue','-h','-u','sunyiq','-o','%i|%j|%T|%Z'],capture_output=True,text=True,timeout=30)
assert queue.returncode==0 and not any(line.split('|')[1].startswith('zj_gru_cov_mat_aud_') for line in queue.stdout.splitlines())
(root/'records').mkdir(exist_ok=False)
record={'status':'saved_matrix_deployment_directory_repaired_before_first_submission','checked_at_beijing':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
    'failed_deployment_sequence':432,'failed_receipt_sha256':'794483eb73edd55e257ce40f23aad0b40c8a067db02eb8eadd3f4211c44a8e33',
    'prior_submission_attempt_exists':False,'prior_scheduler_jobs_exists':False,'prior_evidence_exists':False,
    'all_deployed_file_hashes_match_original_payload':True,'new_scientific_source_files_written':False,
    'original_diagnostic_not_resubmitted':True,'queue':queue.stdout}
with (root/'records/package_deployment_repair.json').open('x') as f:json.dump(record,f,sort_keys=True,indent=2);f.write('\n')
print(json.dumps(record,sort_keys=True),flush=True)
PY
python -B /data1/home/sunyiq/zhenjiang_covariance_saved_matrix_audit_20261014_001/hpc/submit_saved_matrix_audit.py
python -B /data1/home/sunyiq/zhenjiang_covariance_saved_matrix_audit_20261014_001/hpc/probe_saved_matrix_audit.py
