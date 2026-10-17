#!/usr/bin/env bash
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
export CUDA_VISIBLE_DEVICES=""
python -B - <<'DEPLOY_SQRT_GPU'
import hashlib,json,pathlib,subprocess,sys,tarfile
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_sqrt_covariance_repair_20261017_001')
assert root.is_dir()
assert hashlib.sha256((root/'package_manifest.json').read_bytes()).hexdigest()=='374631c1299907073f3a398c9d166c1e01dd5936c5209b9851d63b28d9b0a332'
assert hashlib.sha256((root/'records/stored_operand_cpu_admission.json').read_bytes()).hexdigest()=='725d0a4c867a9e2811389d9183c980258d8eccc495a68be1f6f9a564b613236b'
inbox=pathlib.Path('inbox/zhenjiang-six-source-four-target-ukf')
assert int((inbox/'seq').read_text())==576
payload=inbox/'payload_complete_comparison_20261006_576.tar.gz'
assert hashlib.sha256(payload.read_bytes()).hexdigest()=='ff6793d2ef38115d6aa05c033db73623e7e96748fc198d4b65c37020893899b7'
with tarfile.open(payload,'r:gz') as archive:
 members=archive.getmembers()
 assert len(members)==10
 assert all(m.isfile() and not pathlib.PurePosixPath(m.name).is_absolute() and '..' not in pathlib.PurePosixPath(m.name).parts for m in members)
 assert all(not (root/m.name).exists() for m in members), 'reconcile additive deployment; never overwrite'
 for member in members:
  path=root/member.name;path.parent.mkdir(parents=True,exist_ok=True)
  with path.open('xb') as stream:stream.write(archive.extractfile(member).read())
(root/'logs').mkdir(exist_ok=True)
print(json.dumps({'status':'sqrt_gpu_additive_package_deployed','root':str(root),'manifest_sha256':hashlib.sha256((root/'gpu_package_manifest.json').read_bytes()).hexdigest(),'formal_epochs_added':0}),flush=True)
subprocess.run([sys.executable,'-B',str(root/'hpc/gpu_workflow.py'),'submit'],cwd=root,check=True)
subprocess.run([sys.executable,'-B',str(root/'hpc/gpu_workflow.py'),'probe'],cwd=root,check=True)
DEPLOY_SQRT_GPU
